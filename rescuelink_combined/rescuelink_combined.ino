#include <Wire.h>
#include <math.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_BME680.h>
#include <RescueLink_Disaster_Ai_2.0_inferencing.h>

#include "edge-impulse-sdk/tensorflow/lite/micro/all_ops_resolver.h"
#include "edge-impulse-sdk/tensorflow/lite/micro/micro_interpreter.h"
#include "edge-impulse-sdk/tensorflow/lite/schema/schema_generated.h"
#include "fire_model_data.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- UUID ---
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// --- PİNLER ---
#define I2C_SDA    10
#define I2C_SCL    11
#define BUTTON_PIN  5
#define BUZZER_PIN  4
#define RXD2       18
#define TXD2       17

// --- BUZZER ---
const int frekans    = 2000;
const int cozunurluk = 8;
int sesSeviyesi      = 100;

// --- DURUM & HAFIZA ---
int   calisma_modu = 0;
bool  ilk_acilis   = true;
const int MPU_ADDR = 0x68;

// 🛠️ YENİ: Cihazın kendi hafızasında tuttuğu son koordinatlar
float son_lat = 0.0;
float son_lon = 0.0;

// --- KİLİTLER (MUTEX) ---
SemaphoreHandle_t fire_index_mutex;
SemaphoreHandle_t i2c_mutex;
SemaphoreHandle_t lora_mutex;

// --- DEPREM AI ---
float features[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
int   feature_index          = 0;
bool  deprem_kalkani_aktif   = false;
unsigned long deprem_kalkani_bitis = 0;

// --- ENKAZ ---
int  vurusSayaci = 0;
unsigned long sonVurusZamani = 0;
float onceki_magnitude = 9.81;

// --- BME680 ---
Adafruit_BME680 bme;
float baseline_gas   = 0, baseline_temp = 0;
float baseline_hum   = 0, baseline_pres = 0;
bool  baseline_hazir = false;
unsigned long yangin_alarm_bitis = 0;
int   baseline_sayac = 0;
const int BASELINE_SAMPLE_COUNT = 24;
bool onceki_koma_modu = false;

// Threshold
#define GAS_RATIO_FIRE        0.10
#define GAS_RATIO_AIR_QUALITY 0.30
#define TEMP_DELTA_FIRE       15.0
#define HUMIDITY_DELTA_HIGH   25.0
#define DEPREM_STD_THRESHOLD  0.3

// --- TFLite Micro (Yangın AI) ---
#define FIRE_INPUT_SIZE   200
#define FIRE_OUTPUT_SIZE  4
#define TENSOR_ARENA_SIZE (16 * 1024)

namespace {
  tflite::AllOpsResolver       fire_resolver;
  const tflite::Model*         fire_model_ptr   = nullptr;
  tflite::MicroInterpreter*    fire_interpreter = nullptr;
  TfLiteTensor*                fire_input       = nullptr;
  TfLiteTensor*                fire_output      = nullptr;
  uint8_t tensor_arena[TENSOR_ARENA_SIZE];
}

float fire_features[FIRE_INPUT_SIZE];
int   fire_feature_index = 0;

const char* fire_labels[4] = {"air_quality_bad", "fire", "humidity", "normal"};

// --- BLE ---
BLECharacteristic* pTxCharacteristic;
bool deviceConnected = false;

class MyServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer)    { deviceConnected = true; }
    void onDisconnect(BLEServer* pServer) { deviceConnected = false; }
};

// --- BLE RX (GELEN VERİ DİNLEME - HAM BİNARY OKUMA) ---
class MyRxCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        // String belasını tamamen bıraktık, doğrudan donanıma gelen ham byte'ları alıyoruz!
        uint8_t* rxData = pCharacteristic->getData();
        size_t rxLength = pCharacteristic->getLength();

        if (rxLength > 0) {
            // 1. Ham Binary GPS Paketi mi? (Uzunluk 12 ve Header 0x01 ise)
            if (rxLength == 12 && rxData[0] == 0x01) {
                memcpy(&son_lat, rxData + 2, 4);
                memcpy(&son_lon, rxData + 6, 4);
                Serial.printf("📍 [GPS BİNARY] Konum güncellendi: Lat=%.4f, Lon=%.4f\n", son_lat, son_lon);
            } 
            else {
                // Eski string "LOC|" formatı gelme ihtimaline karşı (Geriye Dönük Uyum)
                String rxString = "";
                for (int i = 0; i < rxLength; i++) rxString += (char)rxData[i];

                if (rxString.startsWith("LOC|")) {
                    int firstPipe = rxString.indexOf('|');
                    int secondPipe = rxString.indexOf('|', firstPipe + 1);
                    if (firstPipe > 0 && secondPipe > 0) {
                        son_lat = rxString.substring(firstPipe + 1, secondPipe).toFloat();
                        son_lon = rxString.substring(secondPipe + 1).toFloat();
                        Serial.printf("📍 [GPS METİN] Konum güncellendi: Lat=%.4f, Lon=%.4f\n", son_lat, son_lon);
                    }
                }
                else {
                    // Standart 1 Byte Komutlar
                    uint8_t cmd = rxData[0];
                    
                    if (cmd == 0x99) {
                        yangin_alarm_bitis = 0;
                        ledcWrite(BUZZER_PIN, 0);
                        Serial.println("🔇 [SİSTEM] Alarm susturuldu.");
                    }
                    else if (cmd == 0x55) {
                        calisma_modu = 4;
                        Serial.println("🔋 [KOMA] Koma Modu AÇILDI.");
                        ledcWrite(BUZZER_PIN, 80); vTaskDelay(100 / portTICK_PERIOD_MS); ledcWrite(BUZZER_PIN, 0);
                    }
                    else if (cmd == 0x56) {
                        calisma_modu = 3;
                        Serial.println("🟢 [KOMA] Koma Modu KAPATILDI.");
                        ledcWrite(BUZZER_PIN, 80); vTaskDelay(100 / portTICK_PERIOD_MS);
                        vTaskDelay(100 / portTICK_PERIOD_MS);
                        ledcWrite(BUZZER_PIN, 80); vTaskDelay(100 / portTICK_PERIOD_MS); ledcWrite(BUZZER_PIN, 0);
                    }
                }
            }
        }
    }
};

void sendBleCommand(uint8_t command) {
    if (deviceConnected) {
        uint8_t cmd[1] = {command};
        pTxCharacteristic->setValue(cmd, 1);
        pTxCharacteristic->notify();
    }
}

// LoRa Üzerinden Hafızalı (Konumlu) Binary Paket Gönderme
void sendLoRaBinary(uint8_t type) {
    uint8_t packet[12] = {0}; 
    packet[0] = 0x01;  // Header
    packet[1] = type;  // Acil Durum Tipi
    
    // Float değerleri (4 Byte) doğrudan byte dizisine yapıştır
    memcpy(&packet[2], &son_lat, sizeof(float));
    memcpy(&packet[6], &son_lon, sizeof(float));

    // 🛠️ YAMA 2: Otonom sinyallerde kişi sayısını varsayılan 1 yap (AFAD Önceliği)
    packet[11] = 1;
    
    // Kilit al ve gönder
    if (xSemaphoreTake(lora_mutex, portMAX_DELAY)) {
        Serial2.write(packet, 12);
        xSemaphoreGive(lora_mutex);
    }
}

void checkButton() {
    static unsigned long son_basmaZamani = 0;
    if (digitalRead(BUTTON_PIN) == LOW && millis() - son_basmaZamani > 200) {
        son_basmaZamani = millis();
        calisma_modu++;
        if (calisma_modu > 4) calisma_modu = 0;

        feature_index = 0;
        if (xSemaphoreTake(fire_index_mutex, portMAX_DELAY)) {
            fire_feature_index = 0;
            xSemaphoreGive(fire_index_mutex);
        }
        vurusSayaci          = 0;
        deprem_kalkani_aktif = false;
        ledcWrite(BUZZER_PIN, 0);

        Serial.println("\n*******************************************");
        if      (calisma_modu == 0) Serial.println("⛔ SİSTEM BEKLEMEDE");
        else if (calisma_modu == 1) Serial.println("🟢 MOD 1: DEPREM");
        else if (calisma_modu == 2) Serial.println("🔥 MOD 2: YANGIN");
        else if (calisma_modu == 3) Serial.println("🛡️ MOD 3: HİBRİT");
        else if (calisma_modu == 4) Serial.println("🎯 MOD 4: ENKAZ (Koma)");
        Serial.println("*******************************************\n");

        ledcWrite(BUZZER_PIN, 80); vTaskDelay(80 / portTICK_PERIOD_MS); ledcWrite(BUZZER_PIN, 0);
    }
}

void bmeBaselineGuncelle(float temp, float hum, float gas, float pres) {
    baseline_temp += temp; baseline_hum  += hum;
    baseline_gas  += gas;  baseline_pres += pres;
    baseline_sayac++;
    if (baseline_sayac >= BASELINE_SAMPLE_COUNT) {
        baseline_temp /= BASELINE_SAMPLE_COUNT;
        baseline_hum  /= BASELINE_SAMPLE_COUNT;
        baseline_gas  /= BASELINE_SAMPLE_COUNT;
        baseline_pres /= BASELINE_SAMPLE_COUNT;
        baseline_hazir = true;
        Serial.printf("✅ Baseline: T=%.1f H=%.1f G=%.1f P=%.1f\n",
            baseline_temp, baseline_hum, baseline_gas, baseline_pres);
    }
}

void yanginInference(float temp, float hum, float gas, float pres) {
    if (!baseline_hazir || fire_interpreter == nullptr) return;
    if (millis() < yangin_alarm_bitis) return;

    float gas_ratio      = gas  / baseline_gas;
    float temp_delta     = temp - baseline_temp;
    float humidity_delta = hum  - baseline_hum;
    float pressure_delta = pres - baseline_pres;

    if (!xSemaphoreTake(fire_index_mutex, 0)) return;

    if (fire_feature_index >= FIRE_INPUT_SIZE) {
        // 🛠️ YAMA 3: Performans için memmove kullanımı (Kayar Pencere)
        memmove(fire_features, fire_features + 4, (FIRE_INPUT_SIZE - 4) * sizeof(float));
        fire_feature_index = FIRE_INPUT_SIZE - 4; 
    }

    fire_features[fire_feature_index++] = gas_ratio;
    fire_features[fire_feature_index++] = temp_delta;
    fire_features[fire_feature_index++] = humidity_delta;
    fire_features[fire_feature_index++] = pressure_delta;
    bool tamam = (fire_feature_index >= FIRE_INPUT_SIZE);
    xSemaphoreGive(fire_index_mutex);

    if (!tamam) return;

    bool threshold_fire     = (gas_ratio < GAS_RATIO_FIRE) && (temp_delta > TEMP_DELTA_FIRE);
    bool threshold_aq_bad   = (gas_ratio < GAS_RATIO_AIR_QUALITY) && (temp_delta < 3.0);
    bool threshold_humidity = (humidity_delta > HUMIDITY_DELTA_HIGH);

    for (int i = 0; i < FIRE_INPUT_SIZE; i++)
        fire_input->data.f[i] = fire_features[i];

    if (fire_interpreter->Invoke() != kTfLiteOk) {
        Serial.println("❌ Yangın inference hatası!");
        return;
    }

    float conf_air  = fire_output->data.f[0];
    float conf_fire = fire_output->data.f[1];
    float conf_hum  = fire_output->data.f[2];
    float conf_norm = fire_output->data.f[3];

    Serial.printf("🔥 Yangın AI: fire=%%%.0f aq=%%%.0f hum=%%%.0f norm=%%%.0f\n",
        conf_fire*100, conf_air*100, conf_hum*100, conf_norm*100);

    if ((conf_fire > 0.80) && threshold_fire) {
        ledcWrite(BUZZER_PIN, sesSeviyesi);
        sendBleCommand(0x0C); 
        Serial.println("🚨 [YANGIN] YANGIN ALGILANDI!");
        yangin_alarm_bitis = millis() + 30000;
    } else if ((conf_air > 0.70) || threshold_aq_bad) {
        sendBleCommand(0x0E);
        Serial.println("⚠️ [HAVA] Hava kalitesi kötü!");
    } else if ((conf_hum > 0.70) || threshold_humidity) {
        sendBleCommand(0x0F);
        Serial.println("💧 [NEM] Yüksek nem!");
    } else if (conf_fire > 0.50 && !threshold_fire) {
        sendBleCommand(0x10);
        Serial.println("❓ [BELİRSİZ] Kullanıcı onayı gerekiyor.");
    }
}

// =========================================================================
// CORE 0: DEPREM + ENKAZ
// =========================================================================
void AiAndSensorTask(void* pvParameters) {
    for (;;) {
        checkButton();

        if (calisma_modu == 0) {
            if (ilk_acilis) {
                Serial.println("Sistem hazır. Butona bas.");
                ilk_acilis = false;
            }
            vTaskDelay(EI_CLASSIFIER_INTERVAL_MS / portTICK_PERIOD_MS);
            continue;
        }

        int16_t ax_raw = 0, ay_raw = 0, az_raw = 0;
        if (xSemaphoreTake(i2c_mutex, portMAX_DELAY)) {
            Wire.beginTransmission(MPU_ADDR);
            Wire.write(0x3B);
            
            if (Wire.endTransmission(false) == 0) {
                if (Wire.requestFrom(MPU_ADDR, 6, true) == 6) {
                    ax_raw = Wire.read() << 8 | Wire.read();
                    ay_raw = Wire.read() << 8 | Wire.read();
                    az_raw = Wire.read() << 8 | Wire.read();
                }
            }
            xSemaphoreGive(i2c_mutex);
        }

        float ax_ms2 = (ax_raw / 16384.0) * 9.81;
        float ay_ms2 = (ay_raw / 16384.0) * 9.81;
        float az_ms2 = (az_raw / 16384.0) * 9.81;
        float magnitude = sqrt(ax_ms2*ax_ms2 + ay_ms2*ay_ms2 + az_ms2*az_ms2);

        if (calisma_modu == 1 || calisma_modu == 3) {
            features[feature_index++] = az_ms2;

            if (feature_index >= EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE) {
                feature_index = 0;
                signal_t signal;
                numpy::signal_from_buffer(features, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, &signal);
                ei_impulse_result_t result = {0};

                if (run_classifier(&signal, &result, false) == EI_IMPULSE_OK) {
                    float ai_sonucu        = result.classification[0].value;
                    float anomali_seviyesi = (result.anomaly + 1.2) * 25.0;
                    if (anomali_seviyesi < 0)   anomali_seviyesi = 0;
                    if (anomali_seviyesi > 100) anomali_seviyesi = 100;

                    float mean = 0;
                    for (int i = 0; i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; i++)
                        mean += features[i];
                    mean /= EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE;

                    float varyans = 0;
                    for (int i = 0; i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; i++)
                        varyans += (features[i] - mean) * (features[i] - mean);
                    varyans /= EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE;
                    float std_dev = sqrt(varyans);

                    bool gercek_sarsinti = (std_dev > DEPREM_STD_THRESHOLD);

                    unsigned long su_an = millis();
                    if (!deprem_kalkani_aktif) {
                        if (ai_sonucu > 0.70 && gercek_sarsinti) {
                            ledcWrite(BUZZER_PIN, sesSeviyesi);
                            sendBleCommand(0x0A);
                            Serial.println("🚨 [DEPREM] DEPREM ALGILANDI!");
                            deprem_kalkani_aktif = true;
                            deprem_kalkani_bitis = su_an + 30000;
                        } else if (ai_sonucu > 0.50 && ai_sonucu <= 0.70 && gercek_sarsinti) {
                            sendBleCommand(0x0B);
                            Serial.println("⚠️ [MUHTEMEL DEPREM] %50-70 arası, onay bekleniyor.");
                        } else if (anomali_seviyesi > 20.0 && gercek_sarsinti) {
                            sendBleCommand(0x0B);
                            Serial.println("⚠️ [ANOMALİ] Tanımlanamayan sarsıntı!");
                        }
                    } else {
                        if (su_an > deprem_kalkani_bitis) {
                            deprem_kalkani_aktif = false;
                            ledcWrite(BUZZER_PIN, 0);
                            Serial.println("🟢 Deprem süreci bitti, normale dönüldü.");
                        }
                    }
                }
            }
        } else if (calisma_modu == 4) {
            bool esik_alti  = abs(onceki_magnitude - 9.81) <= 5.0;
            bool esik_ustu  = abs(magnitude - 9.81) > 5.0;
            onceki_magnitude = magnitude;

            if (esik_alti && esik_ustu) {
                unsigned long su_an = millis();
                if (su_an - sonVurusZamani > 150) {
                    vurusSayaci++;
                    sonVurusZamani = su_an;
                    Serial.printf("🎯 Vuruş: %d/4\n", vurusSayaci);
                    if (vurusSayaci >= 4) {
                        sendBleCommand(0x0D);
                        sendLoRaBinary(0x04);
                        vurusSayaci = 0;
                        ledcWrite(BUZZER_PIN, 50); vTaskDelay(150 / portTICK_PERIOD_MS); ledcWrite(BUZZER_PIN, 0);
                    }
                }
            }
            if (millis() - sonVurusZamani > 4000) vurusSayaci = 0;
        }

        vTaskDelay(EI_CLASSIFIER_INTERVAL_MS / portTICK_PERIOD_MS);
    }
}

// =========================================================================
// CORE 1: BME680 YANGIN
// =========================================================================
void FireSensorTask(void* pvParameters) {
    if (!bme.begin(0x76)) {
        Serial.println("❌ BME680 bulunamadı!");
        vTaskDelete(NULL);
        return;
    }
    bme.setTemperatureOversampling(BME680_OS_8X);
    bme.setHumidityOversampling(BME680_OS_2X);
    bme.setPressureOversampling(BME680_OS_4X);
    bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
    bme.setGasHeater(320, 150);
    Serial.println("✅ BME680 hazır.");

    for (;;) {
        if (yangin_alarm_bitis > 0 && millis() >= yangin_alarm_bitis) {
            ledcWrite(BUZZER_PIN, 0);
            yangin_alarm_bitis = 0;
        }

        if (calisma_modu == 4) {
            if (!onceki_koma_modu) {
                bme.setGasHeater(0, 0);
                onceki_koma_modu = true;
                Serial.println("🔋 [KOMA] BME680 Isıtıcısı kapatıldı.");
            }
            vTaskDelay(5000 / portTICK_PERIOD_MS);
            continue; 
        } else {
            if (onceki_koma_modu) {
                bme.setGasHeater(320, 150);
                onceki_koma_modu = false;
                Serial.println("🔥 [NORMAL] BME680 Isıtıcısı tekrar aktif.");
                vTaskDelay(2000 / portTICK_PERIOD_MS); 
            }
        }

        if (calisma_modu == 2 || calisma_modu == 3) {
            bool readSuccess = false;
            if (xSemaphoreTake(i2c_mutex, portMAX_DELAY)) {
                readSuccess = bme.performReading();
                xSemaphoreGive(i2c_mutex);
            }

            if (!readSuccess) {
                vTaskDelay(1000 / portTICK_PERIOD_MS);
                continue;
            }
            float temp = bme.temperature;
            float hum  = bme.humidity;
            float gas  = bme.gas_resistance / 1000.0;
            float pres = bme.pressure / 100.0;

            if (deviceConnected && baseline_hazir) {
                char telBuf[64];
                sprintf(telBuf, "TEL|%.1f|%.0f|%.0f|%.0f", temp, hum, pres, gas);
                pTxCharacteristic->setValue((uint8_t*)telBuf, strlen(telBuf));
                pTxCharacteristic->notify();
            }

            if (!baseline_hazir) {
                bmeBaselineGuncelle(temp, hum, gas, pres);
            } else {
                yanginInference(temp, hum, gas, pres);
            }
        }
        vTaskDelay(5000 / portTICK_PERIOD_MS);
    }
}

// =========================================================================
void setup() {
    fire_index_mutex = xSemaphoreCreateMutex();
    i2c_mutex = xSemaphoreCreateMutex();
    lora_mutex = xSemaphoreCreateMutex(); 

    Serial.begin(115200);
    Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2);

    ledcAttach(BUZZER_PIN, frekans, cozunurluk);
    ledcWrite(BUZZER_PIN, 0);
    pinMode(BUTTON_PIN, INPUT_PULLUP);

    Wire.begin(I2C_SDA, I2C_SCL);
    Wire.beginTransmission(MPU_ADDR); Wire.write(0x6B); Wire.write(0); Wire.endTransmission();

    fire_model_ptr = tflite::GetModel(fire_model_data);
    if (fire_model_ptr->version() != TFLITE_SCHEMA_VERSION) {
        Serial.println("❌ TFLite model şema uyumsuz!");
    } else {
        static tflite::MicroInterpreter static_interpreter(
            fire_model_ptr, fire_resolver, tensor_arena, TENSOR_ARENA_SIZE);
        fire_interpreter = &static_interpreter;

        if (fire_interpreter->AllocateTensors(true) != kTfLiteOk) {
            Serial.println("❌ TFLite tensor allocate hatası!");
            fire_interpreter = nullptr;
        } else {
            fire_input  = fire_interpreter->input(0);
            fire_output = fire_interpreter->output(0);
            Serial.println("✅ Yangın TFLite modeli hazır.");
        }
    }

    BLEDevice::init("RescueLink_Node");
    BLEServer* pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());
    BLEService* pService = pServer->createService(SERVICE_UUID);

    pTxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
    pTxCharacteristic->addDescriptor(new BLE2902());

    BLECharacteristic* pRxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
    pRxCharacteristic->setCallbacks(new MyRxCallbacks());

    pService->start();
    pServer->getAdvertising()->start();

    xTaskCreatePinnedToCore(AiAndSensorTask, "AiAndSensorTask", 16384, NULL, 1, NULL, 0);
    xTaskCreatePinnedToCore(FireSensorTask,  "FireSensorTask",  16384, NULL, 1, NULL, 1);

    Serial.println("\n🚀 RESCUELINK V4.6 (Tam Final & Binary Korumalı) YÜKLENDİ!");
}

// =========================================================================
// ANA DÖNGÜ (Heartbeat / Yaşam Sinyali)
// =========================================================================
void loop() {
    static unsigned long last_heartbeat = 0;

    if (millis() - last_heartbeat > 3600000) {
        last_heartbeat = millis();
        sendBleCommand(0x12);
        sendLoRaBinary(0x12);
    }

    vTaskDelay(1000 / portTICK_PERIOD_MS);
}