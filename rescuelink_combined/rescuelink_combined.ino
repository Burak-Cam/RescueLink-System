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
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <ArduinoJson.h>    // [YENİ] GitHub API JSON parse
#include <Update.h>         // [YENİ] OTA flash

// [YENİ] Edge Impulse API — anahtarınızı buraya yazın
#define EI_API_KEY "ei_ce12f316ea0303e0a6bcedf05f26bf2bac373a6749b75e8a"

// [YENİ] Cloud OTA — GitHub üzerinden otomatik güncelleme
#define FIRMWARE_VERSION  "v0.9"
#define GITHUB_REPO       "Burak-Cam/RescueLink-System"
#define OTA_BIN_NAME      "firmware.bin"

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

// --- CİHAZ KİMLİKLERİ ---
#define NODE_ID      0x01   // Bu cihazın kimliği (Kurye cihazına yüklerken bunu 0x02 yap!)
#define GATEWAY_ID   0x00   // Merkezin kimliği

// --- BUZZER ---
const int frekans    = 2000;
const int cozunurluk = 8;
int sesSeviyesi      = 100;

// --- DURUM & HAFIZA ---
int   calisma_modu = 0;
bool  ilk_acilis   = true;
const int MPU_ADDR = 0x68;

float son_lat = 0.0;
float son_lon = 0.0;

// 🔥 YENİ ZIRH: Kıyamet Hafızası (Deprem onaylandı mı?)
bool gercek_bir_deprem_yasandi_mi = false; 

// --- PAKET SAYAÇ ---
uint8_t paket_sayaci = 0;

// --- MESH (RÖLE) HAFIZASI ---
uint8_t global_msg_id = 0;      
uint8_t msg_cache[10] = {0};    
int cache_index = 0;

bool isMessageSeen(uint8_t msg_id) {
    for (int i = 0; i < 10; i++) {
        if (msg_cache[i] == msg_id) return true;
    }
    return false;
}

void addToCache(uint8_t msg_id) {
    msg_cache[cache_index] = msg_id;
    cache_index = (cache_index + 1) % 10;
}

// --- KİLİTLER (MUTEX) ---
SemaphoreHandle_t fire_index_mutex;
SemaphoreHandle_t i2c_mutex;
SemaphoreHandle_t lora_mutex;

// [YENİ] WiFi BLE provisioning + Anomali etiket pipeline
Preferences preferences;
String wifi_ssid = "";
String wifi_pass = "";

float anomali_features_kopyasi[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
bool  anomali_etiket_bekleniyor = false;
unsigned long anomali_bekleme_baslangic = 0;
bool  anomali_upload_hazir = false;
char  anomali_upload_label[32] = {0};

// --- OTA ---
String ota_latest_tag = "";

// --- BLE OTA ---
bool   ble_ota_aktif  = false;
size_t ble_ota_toplam = 0;
size_t ble_ota_alindi = 0;
volatile bool ota_baslat_istegi = false;

// --- WiFi bağlantı isteği (BLE callback'ten güvenli tetikleme) ---
volatile bool wifi_baglan_istegi = false;
volatile bool ilk_baglanti_heartbeat = false;
volatile bool konum_geldi_heartbeat_at = false;

// --- DEPREM AI ---
float features[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
int   feature_index          = 0;
bool  deprem_kalkani_aktif   = false;
unsigned long deprem_kalkani_bitis = 0;

// --- SAĞLIK & KİŞİ (Telefondan BLE ile gelir) ---
uint8_t son_saglik_durumu = 0;
uint8_t son_kisi_sayisi   = 1;

// --- ENKAZ ---
int  vurusSayaci = 0;
unsigned long sonVurusZamani = 0;
float onceki_magnitude = 9.81;

// --- BME680 ---
Adafruit_BME680 bme;
float baseline_gas   = 0, baseline_temp = 0;
float baseline_hum   = 0, baseline_pres = 0;
bool  baseline_hazir = false;
bool  yangin_alarm_aktif = false;
int   son_bildirim       = 0;
int   normal_sayac       = 0;
int   baseline_sayac     = 0;
int   adaptive_sayac     = 0;
const int BASELINE_SAMPLE_COUNT  = 24;
const int ADAPTIVE_UPDATE_EVERY  = 10;   // her 10 normal okumada güncelle (~50sn)
const float ALPHA_TEMP_HUM_PRES  = 0.03f;
const float ALPHA_GAS            = 0.01f;
bool onceki_afet_modu = false;

#define DEPREM_STD_THRESHOLD  0.3

// --- TFLite Micro (Yangın AI) ---
#define FIRE_INPUT_SIZE   40
#define FIRE_OUTPUT_SIZE  4
#define TENSOR_ARENA_SIZE (16 * 1024)

namespace {
  tflite::AllOpsResolver       fire_resolver;
  const tflite::Model* fire_model_ptr   = nullptr;
  tflite::MicroInterpreter* fire_interpreter = nullptr;
  TfLiteTensor* fire_input       = nullptr;
  TfLiteTensor* fire_output      = nullptr;
  uint8_t* tensor_arena     = nullptr;
}

float fire_features[FIRE_INPUT_SIZE];
int   fire_feature_index = 0;

// --- TEST MODU (Mod 5) ---
volatile bool    yangin_test_pending = false;
volatile float   yangin_test_vals[4] = {1.0f, 0.0f, 0.0f, 0.0f};
volatile bool    deprem_test_pending = false;
volatile uint8_t deprem_test_type   = 0; // 0=normal 1=hafif 2=guclu

const char* fire_labels[4] = {"normal", "hava kalitesi", "yangın", "gaz kaçağı"};

// --- BLE ---
BLECharacteristic* pTxCharacteristic;
bool deviceConnected = false;
QueueHandle_t ble_cmd_queue = nullptr; // Task'lardan loop()'a güvenli BLE dispatch

// İLERİ BİLDİRİMLER
void sendLoRaBinary(uint8_t type);
void sendBleCommand(uint8_t command);
void wifiConnect();

// --- BLE BAĞLANTI YÖNETİMİ (KOPMA FIX) ---
class MyServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) { 
        deviceConnected = true; 
        Serial.println("📱 [BLE] Telefon bağlandı.");
    }
    void onDisconnect(BLEServer* pServer) { 
        deviceConnected = false; 
        pServer->startAdvertising(); 
        Serial.println("❌ [BLE] Bağlantı koptu. Advertising (Görünürlük) tekrar başlatıldı.");
    }
};

class MyRxCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        uint8_t* rxData = pCharacteristic->getData();
        size_t rxLength = pCharacteristic->getLength();

        if (rxLength > 0) {
            if (ble_ota_aktif) {
                if (rxLength == 11 && memcmp(rxData, "OTA_BLE|END", 11) == 0) {
                    if (Update.end(true)) {
                        Serial.println("✅ [BLE OTA] Flash tamamlandı, yeniden başlatılıyor...");
                        sendBleCommand(0x23);
                        delay(500);
                        ESP.restart();
                    } else {
                        Serial.printf("❌ [BLE OTA] Update.end hatası! %s\n", Update.errorString());
                        sendBleCommand(0x22);
                        ble_ota_aktif = false;
                    }
                } else {
                    size_t written = Update.write(rxData, rxLength);
                    ble_ota_alindi += written;
                    int pct = (ble_ota_toplam > 0) ? (int)(ble_ota_alindi * 100 / ble_ota_toplam) : 0;
                    if (written == rxLength) {
                        static int son_yuzde = -1;
                        if (pct != son_yuzde && pct % 5 == 0) {
                            Serial.printf("⬇️ [BLE OTA] %%%d (%d/%d byte)\n", pct, ble_ota_alindi, ble_ota_toplam);
                            son_yuzde = pct;
                        } else if (ble_ota_alindi == 256) {
                           Serial.printf("⬇️ [BLE OTA] İLK PAKET ALINDI! (%d/%d byte)\n", ble_ota_alindi, ble_ota_toplam);
                        }
                        
                        sendBleCommand(0x21); // ACK gönder
                    } else {
                        Serial.printf("❌ [BLE OTA] Yazma hatası! Beklenen: %d, Yazılan: %d\n", rxLength, written);
                        sendBleCommand(0x22);
                        ble_ota_aktif = false;
                    }
                }
                return;
            }

            if (rxLength == 1 && rxData[0] == 0xF0) {
                ledcWrite(BUZZER_PIN, 0);
                yangin_alarm_aktif = false;
                son_bildirim       = 0;
                normal_sayac       = 0;
                if (xSemaphoreTake(fire_index_mutex, portMAX_DELAY)) {
                    fire_feature_index = 0;
                    xSemaphoreGive(fire_index_mutex);
                }
                baseline_hazir = false;
                baseline_sayac = 0;
                baseline_temp = baseline_hum = baseline_gas = baseline_pres = 0.0f;
                Serial.println("🔄 [ONAY] 'Sorun yok' alındı — baseline yeniden başlıyor...");
            }
            else if (rxLength == 12 && rxData[0] == 0x01) {
                uint8_t afet_tipi = rxData[1];
                memcpy(&son_lat, rxData + 2, 4);
                memcpy(&son_lon, rxData + 6, 4);
                son_saglik_durumu = rxData[10];
                son_kisi_sayisi   = rxData[11];
                Serial.printf("📍 [GPS BİNARY] Konum güncellendi: Lat=%.4f, Lon=%.4f\n", son_lat, son_lon);
                Serial.printf("[BİLGİ] Sağlık: %d, Kişi: %d\n", son_saglik_durumu, son_kisi_sayisi);

                if (afet_tipi == 0x12) {
                    Serial.println("ℹ️ [SİSTEM] Telefondan Heartbeat (0x12) yansıması geldi, UART çarpışması önlendi.");
                } else {
                    sendLoRaBinary(afet_tipi);
                    Serial.println("📡 [LORA] Telefondan gelen Manuel SOS doğrudan fırlatıldı!");
                }
            } 
            else {
                String rxString = "";
                for (int i = 0; i < rxLength; i++) rxString += (char)rxData[i];

                if (rxString.startsWith("WIFI|")) {
                    int p1 = rxString.indexOf('|');
                    int p2 = rxString.indexOf('|', p1 + 1);
                    if (p1 > 0 && p2 > 0) {
                        wifi_ssid = rxString.substring(p1 + 1, p2);
                        wifi_pass = rxString.substring(p2 + 1);
                        preferences.begin("rescuelink", false);
                        preferences.putString("ssid", wifi_ssid);
                        preferences.putString("pass", wifi_pass);
                        preferences.end();
                        Serial.printf("✅ [WiFi] Bilgiler kaydedildi: %s — Bağlantı başlatılıyor...\n", wifi_ssid.c_str());
                        wifi_baglan_istegi = true;
                    }
                }
                // Anomali etiket pipeline
                else if (rxString.startsWith("LABEL|") && anomali_etiket_bekleniyor) {
                    String label = rxString.substring(6);
                    label.trim();
                    strncpy(anomali_upload_label, label.c_str(), 31);
                    anomali_etiket_bekleniyor = false;
                    anomali_upload_hazir = true;
                    Serial.printf("[LABEL] Etiket alındı: %s\n", anomali_upload_label);
                }
                else if (rxString.startsWith("OTA_BLE|")) {
                    String param = rxString.substring(8);
                    ble_ota_toplam = (size_t)param.toInt();
                    
                    if (ble_ota_toplam > 0) {
                        ota_baslat_istegi = true; 
                    } else {
                        sendBleCommand(0x22);
                    }
                }
                else if (rxString.startsWith("LOC|")) {
                    int firstPipe = rxString.indexOf('|');
                    int secondPipe = rxString.indexOf('|', firstPipe + 1);
                    if (firstPipe > 0 && secondPipe > 0) {
                        son_lat = rxString.substring(firstPipe + 1, secondPipe).toFloat();
                        son_lon = rxString.substring(secondPipe + 1).toFloat();
                        Serial.printf("📍 [GPS METİN] Konum güncellendi: Lat=%.4f, Lon=%.4f\n", son_lat, son_lon);
                    }
                }
                else {
                    uint8_t cmd = rxData[0];
                    if (cmd == 0x99) {
                        yangin_alarm_aktif = false;
                        son_bildirim       = 0;
                        normal_sayac       = 0;
                        ledcWrite(BUZZER_PIN, 0);
                        Serial.println("🔇 [SİSTEM] Alarm susturuldu.");
                    }
                    else if (cmd == 0x55) {
                        calisma_modu = 4;
                        Serial.println("🔋 [AFET] Afet Modu AÇILDI.");
                        ledcWrite(BUZZER_PIN, 80); vTaskDelay(100 / portTICK_PERIOD_MS); ledcWrite(BUZZER_PIN, 0);
                    }
                    else if (cmd == 0x56) {
                        calisma_modu = 3;
                        Serial.println("🟢 [AFET] Afet Modu KAPATILDI.");
                        ledcWrite(BUZZER_PIN, 80); vTaskDelay(100 / portTICK_PERIOD_MS);
                        vTaskDelay(100 / portTICK_PERIOD_MS);
                        ledcWrite(BUZZER_PIN, 80); vTaskDelay(100 / portTICK_PERIOD_MS); ledcWrite(BUZZER_PIN, 0);
                    }
                }
            }
        }
    }
};

void wifiConnect() {
    if (wifi_ssid.length() == 0) return;
    if (WiFi.status() == WL_CONNECTED) return;
    WiFi.disconnect(true);
    vTaskDelay(200 / portTICK_PERIOD_MS);
    WiFi.begin(wifi_ssid.c_str(), wifi_pass.c_str());
    int deneme = 0;
    while (WiFi.status() != WL_CONNECTED && deneme < 20) {
        vTaskDelay(500 / portTICK_PERIOD_MS);
        deneme++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        WiFi.setSleep(false);
        Serial.printf("✅ [WiFi] Bağlandı: %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("❌ [WiFi] Bağlanamadı!");
    }
}

void sendToEdgeImpulse(const char* label) {
    if (wifi_ssid.length() == 0) {
        Serial.println("❌ [WiFi] SSID tanımlı değil, veri gönderilemedi.");
        return;
    }
    wifiConnect();
    if (WiFi.status() != WL_CONNECTED) return;

    HTTPClient http;
    http.begin("http://ingestion.edgeimpulse.com/api/training/data");
    http.addHeader("x-api-key",    EI_API_KEY);
    http.addHeader("x-file-name",  "anomali.json");
    http.addHeader("x-label",      label);
    http.addHeader("Content-Type", "application/json");

    String json = "{\"protected\":{\"ver\":\"v1\",\"alg\":\"none\",\"iat\":0},";
    json += "\"signature\":\"0000\",\"payload\":{";
    json += "\"device_type\":\"ESP32S3\",\"interval_ms\":10,";
    json += "\"sensors\":[{\"name\":\"accZ\",\"units\":\"m/s2\"}],\"values\":[";
    for (int i = 0; i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; i++) {
        json += "[" + String(anomali_features_kopyasi[i], 4) + "]";
        if (i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 1) json += ",";
    }
    json += "]}}";

    Serial.printf("💾 [Heap] Serbest: %d byte\n", ESP.getFreeHeap());
    IPAddress eiIP;
    if (WiFi.hostByName("ingestion.edgeimpulse.com", eiIP))
        Serial.printf("✅ [DNS] ingestion.edgeimpulse.com = %s\n", eiIP.toString().c_str());
    else
        Serial.println("❌ [DNS] Çözümleme başarısız! Ağ sorunu.");

    http.setTimeout(15000);
    Serial.printf("📤 [Edge Impulse] POST gönderiliyor, label: %s, boyut: %d byte\n", label, json.length());
    int httpCode = http.POST(json);
    if (httpCode == 200) {
        Serial.printf("✅ [Edge Impulse] Gönderildi! Label: %s\n", label);
    } else {
        Serial.printf("❌ [Edge Impulse] HTTP kod: %d | Sebep: %s\n", httpCode, http.errorToString(httpCode).c_str());
        String responseBody = http.getString();
        if (responseBody.length() > 0)
            Serial.printf("❌ [Edge Impulse] Yanıt: %s\n", responseBody.c_str());
    }
    http.end();
    WiFi.disconnect();
}

void checkOTA() {
    if (wifi_ssid.length() == 0) return;
    wifiConnect();
    if (WiFi.status() != WL_CONNECTED) return;

    vTaskDelay(1000 / portTICK_PERIOD_MS);  

    Serial.printf("🔍 [OTA] GitHub kontrol ediliyor... (Heap: %d)\n", esp_get_free_heap_size());

    WiFiClientSecure client;
    client.setInsecure();
    HTTPClient https;
    https.setTimeout(15000);

    https.begin(client, "https://api.github.com/repos/" GITHUB_REPO "/releases/latest");
    https.addHeader("User-Agent",  "ESP32");
    https.addHeader("Accept",      "application/vnd.github.v3+json");
    https.addHeader("Connection",  "close");
    int code = https.GET();

    if (code != 200) {
        Serial.printf("❌ [OTA] GitHub API hatası: %d (Heap: %d)\n", code, esp_get_free_heap_size());
        https.end();
        return;
    }

    StaticJsonDocument<64> filter;
    filter["tag_name"] = true;

    StaticJsonDocument<256> doc;
    DeserializationError err = deserializeJson(doc, https.getStream(),
                                               DeserializationOption::Filter(filter));
    https.end();

    if (err) {
        Serial.println("❌ [OTA] JSON parse hatası!");
        return;
    }

    String latest_tag = doc["tag_name"].as<String>();
    Serial.printf("📦 [OTA] Mevcut: %s | GitHub: %s\n", FIRMWARE_VERSION, latest_tag.c_str());

    if (latest_tag == FIRMWARE_VERSION) {
        Serial.println("✅ [OTA] Firmware güncel, güncelleme yok.");
        return;
    }

    ota_latest_tag = latest_tag;
    Serial.printf("🆕 [OTA] Yeni versiyon mevcut: %s\n", latest_tag.c_str());

    if (deviceConnected) {
        String notif = "OTA_AVAIL|" + latest_tag;
        pTxCharacteristic->setValue((uint8_t*)notif.c_str(), notif.length());
        pTxCharacteristic->notify();
        Serial.println("📤 [OTA] 'Yeni Güncelleme Var' bildirimi mobile başarıyla GÖNDERİLDİ.");
    } else {
        Serial.println("⚠️ [OTA] Telefon bağlı değil. Bildirim GÖNDERİLEMEDİ.");
    }
}

void sendBleCommand(uint8_t command) {
    if (deviceConnected) {
        uint8_t cmd[1] = {command};
        pTxCharacteristic->setValue(cmd, 1);
        pTxCharacteristic->notify();
    }
}

void queueBleCommand(uint8_t command) {
    if (ble_cmd_queue != nullptr)
        xQueueSend(ble_cmd_queue, &command, 0);
}

// =========================================================================
// LORA DOĞRUDAN GÖNDERİM FONKSİYONU (16 BYTE MESH TOPOLOGY)
// =========================================================================
void sendLoRaBinary(uint8_t type) {
    uint8_t packet[16] = {0}; 
    packet[0] = 0x01;              // Header
    packet[1] = type;              // Acil Durum Tipi
    packet[2] = NODE_ID;           // Gönderen ID
    packet[3] = GATEWAY_ID;        // Hedef ID
    
    paket_sayaci++;
    packet[4] = paket_sayaci;      // Mesaj Sıra No
    packet[5] = 1;                 // TTL (Gateway uyumluluğu için sabit 1)
    
    memcpy(&packet[6], &son_lat, sizeof(float));
    memcpy(&packet[10], &son_lon, sizeof(float));
    packet[14] = son_kisi_sayisi;
    packet[15] = son_saglik_durumu;

    if (xSemaphoreTake(lora_mutex, portMAX_DELAY)) {
        Serial2.write(packet, 16);
        xSemaphoreGive(lora_mutex);
    }
    Serial.printf("📡 [LORA TX] SOS Doğrudan Ateşlendi! Type: %x, PacketID: %d\n", type, paket_sayaci);
}

void checkButton() {
    static unsigned long son_basmaZamani = 0;
    if (digitalRead(BUTTON_PIN) == LOW && millis() - son_basmaZamani > 200) {
        son_basmaZamani = millis();
        calisma_modu++;
        if (calisma_modu > 5) calisma_modu = 0;

        feature_index = 0;
        if (xSemaphoreTake(fire_index_mutex, portMAX_DELAY)) {
            fire_feature_index = 0;
            xSemaphoreGive(fire_index_mutex);
        }
        vurusSayaci               = 0;
        deprem_kalkani_aktif      = false;
        anomali_etiket_bekleniyor = false;
        ledcWrite(BUZZER_PIN, 0);

        if (calisma_modu == 4) {
            setCpuFrequencyMhz(80);
        } else {
            setCpuFrequencyMhz(240);
        }

        Serial.println("\n*******************************************");
        if      (calisma_modu == 0) Serial.println("⛔ SİSTEM BEKLEMEDE");
        else if (calisma_modu == 1) Serial.println("🟢 MOD 1: DEPREM");
        else if (calisma_modu == 2) Serial.println("🔥 MOD 2: YANGIN");
        else if (calisma_modu == 3) Serial.println("🛡️ MOD 3: HİBRİT");
        else if (calisma_modu == 4) Serial.println("🎯 MOD 4: AFET | CPU: 80MHz");
        else if (calisma_modu == 5) Serial.println("🧪 MOD 5: TEST");
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

        if (xSemaphoreTake(fire_index_mutex, portMAX_DELAY)) {
            for (int i = 0; i < FIRE_INPUT_SIZE; i += 4) {
                fire_features[i]     = 1.0f; 
                fire_features[i + 1] = 0.0f; 
                fire_features[i + 2] = 0.0f; 
                fire_features[i + 3] = 0.0f; 
            }
            fire_feature_index = FIRE_INPUT_SIZE; 
            xSemaphoreGive(fire_index_mutex);
        }
        Serial.println("⚡ [AI] Buffer hazır, yangın algılama aktif!");
    }
}

void yanginInferenceRun(bool do_adaptive, float temp, float hum, float gas, float pres) {
    if (fire_interpreter == nullptr) return;

    if (fire_input->type == kTfLiteInt8) {
        float scale  = fire_input->params.scale;
        int32_t zp   = fire_input->params.zero_point;
        for (int i = 0; i < FIRE_INPUT_SIZE; i++) {
            int32_t q = (int32_t)roundf(fire_features[i] / scale) + zp;
            fire_input->data.int8[i] = (int8_t)constrain(q, -128, 127);
        }
    } else {
        for (int i = 0; i < FIRE_INPUT_SIZE; i++)
            fire_input->data.f[i] = fire_features[i];
    }

    if (fire_interpreter->Invoke() != kTfLiteOk) {
        Serial.printf("❌ [AI] Inference hatası! Heap: %d\n", ESP.getFreeHeap());
        return;
    }

    float conf[4];
    if (fire_output->type == kTfLiteInt8) {
        float scale = fire_output->params.scale;
        int32_t zp  = fire_output->params.zero_point;
        for (int i = 0; i < 4; i++)
            conf[i] = (fire_output->data.int8[i] - zp) * scale;
    } else {
        for (int i = 0; i < 4; i++)
            conf[i] = fire_output->data.f[i];
    }

    int max_idx = 0;
    for (int i = 1; i < 4; i++) if (conf[i] > conf[max_idx]) max_idx = i;

    Serial.printf("🧠 [AI] Analizi:\n    normal:%d%% || hava_kalitesi:%d%% || yangın:%d%% || gaz_kaçağı:%d%% → sonuç: %s\n\n",
        (int)(conf[0]*100), (int)(conf[1]*100),
        (int)(conf[2]*100), (int)(conf[3]*100), fire_labels[max_idx]);

    static int yangin_sayac = 0;
    static int kacak_sayac  = 0;

    if (max_idx == 2 && conf[2] > 0.60f) {
        normal_sayac = 0;
        yangin_sayac++; kacak_sayac = 0;
        if (yangin_sayac >= 2) {
            yangin_sayac = 0;
            yangin_alarm_aktif = true;
            ledcWrite(BUZZER_PIN, sesSeviyesi);
            if (son_bildirim != 0x0C) {
                son_bildirim = 0x0C;
                queueBleCommand(0x0C);
                Serial.println("🚨🚨🚨 YANGIN ALGILANDI! 🚨🚨🚨");
            }
        } else {
            Serial.printf("⚠️ [YANGIN] Şüpheli %d/2 — %%%d\n", yangin_sayac, (int)(conf[2]*100));
        }
    } else if (max_idx == 3 && conf[3] > 0.60f) {
        normal_sayac = 0;
        kacak_sayac++; yangin_sayac = 0;
        if (kacak_sayac >= 2) {
            kacak_sayac = 0;
            yangin_alarm_aktif = true;
            ledcWrite(BUZZER_PIN, sesSeviyesi);
            if (son_bildirim != 0x10) {
                son_bildirim = 0x10;
                queueBleCommand(0x10);
                Serial.println("🟡🟡🟡 GAZ KAÇAĞI TESPİT EDİLDİ! 🟡🟡🟡");
                Serial.println("⚠️ Ortamı havalandırın, ateş yakmayın!");
            }
        } else {
            Serial.printf("⚠️ [GAZ KAÇAĞI] Şüpheli %d/2 — %%%d\n", kacak_sayac, (int)(conf[3]*100));
        }
    } else if (max_idx == 1 && conf[1] > 0.65f) {
        normal_sayac = 0;
        yangin_sayac = 0; kacak_sayac = 0;
        Serial.println("💨 [HAVA KALİTESİ] Kötü — Ortamı havalandırın!");
    } else {
        yangin_sayac = 0; kacak_sayac = 0;
        if (yangin_alarm_aktif) {
            normal_sayac++;
            Serial.printf("✅ [AI] Normal okuma %d/5 — alarm için değerlerin düşmesi bekleniyor\n", normal_sayac);
            if (normal_sayac >= 5) {
                normal_sayac       = 0;
                yangin_alarm_aktif = false;
                son_bildirim       = 0;
                ledcWrite(BUZZER_PIN, 0);
                Serial.println("✅ [AI] Değerler normale döndü — alarm kapatıldı.");
            }
        } else {
            normal_sayac = 0;
            son_bildirim = 0;
            if (do_adaptive) {
                adaptive_sayac++;
                if (adaptive_sayac >= ADAPTIVE_UPDATE_EVERY) {
                    adaptive_sayac = 0;
                    baseline_temp += ALPHA_TEMP_HUM_PRES * (temp - baseline_temp);
                    baseline_hum  += ALPHA_TEMP_HUM_PRES * (hum  - baseline_hum);
                    baseline_pres += ALPHA_TEMP_HUM_PRES * (pres - baseline_pres);
                    baseline_gas  += ALPHA_GAS            * (gas  - baseline_gas);
                    Serial.printf("📊 [Baseline] Güncellendi: T=%.1f H=%.1f G=%.1f P=%.1f\n",
                        baseline_temp, baseline_hum, baseline_gas, baseline_pres);
                }
            }
        }
    }
}

void yanginInference(float temp, float hum, float gas, float pres) {
    if (!baseline_hazir || fire_interpreter == nullptr) return;

    if (temp >= 55.0f) {
        queueBleCommand(0x11);
        Serial.printf("🌡️ [KRİTİK SICAKLIK] %.1f°C\n", temp);
    } else if (temp >= 45.0f) {
        queueBleCommand(0x11);
        Serial.printf("🌡️ [YÜKSEK SICAKLIK] %.1f°C\n", temp);
    }

    float gas_ratio      = gas / baseline_gas;
    if (gas_ratio > 1.0f) gas_ratio = 1.0f;
    float temp_delta     = (temp - baseline_temp) / 20.0f;
    float humidity_delta = (hum  - baseline_hum)  / 30.0f;
    float pressure_delta = (pres - baseline_pres) / 10.0f;

    if (!xSemaphoreTake(fire_index_mutex, 0)) return;
    if (fire_feature_index >= FIRE_INPUT_SIZE) {
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

    yanginInferenceRun(true, temp, hum, gas, pres);
}

void runDepremInference() {
    feature_index = 0;
    signal_t signal;
    numpy::signal_from_buffer(features, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, &signal);
    ei_impulse_result_t result = {0};

    if (run_classifier(&signal, &result, false) != EI_IMPULSE_OK) return;

    float ai_sonucu        = result.classification[0].value;
    float anomali_seviyesi = (result.anomaly + 1.2) * 25.0;
    if (anomali_seviyesi < 0)   anomali_seviyesi = 0;
    if (anomali_seviyesi > 100) anomali_seviyesi = 100;

    float mean = 0;
    for (int i = 0; i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; i++) mean += features[i];
    mean /= EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE;

    float varyans = 0;
    for (int i = 0; i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; i++)
        varyans += (features[i] - mean) * (features[i] - mean);
    float std_dev = sqrt(varyans / EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE);

    bool gercek_sarsinti = (std_dev > DEPREM_STD_THRESHOLD);

    Serial.print("🧠 [AI] ");
    for (int j = 0; j < EI_CLASSIFIER_LABEL_COUNT; j++)
        Serial.printf("%s=%.2f ", result.classification[j].label, result.classification[j].value);
    Serial.printf("| std=%.3f sarsinti=%d\n", std_dev, gercek_sarsinti);

    unsigned long su_an = millis();
    if (!deprem_kalkani_aktif) {
        if (ai_sonucu > 0.70 && gercek_sarsinti) {
            ledcWrite(BUZZER_PIN, sesSeviyesi);
            queueBleCommand(0x0A);
            Serial.println("🚨 [DEPREM] DEPREM ALGILANDI!");
            gercek_bir_deprem_yasandi_mi = true;
            deprem_kalkani_aktif = true;
            deprem_kalkani_bitis = su_an + 30000;
        } else if (ai_sonucu > 0.50 && ai_sonucu <= 0.70 && gercek_sarsinti) {
            memcpy(anomali_features_kopyasi, features, sizeof(features));
            anomali_etiket_bekleniyor = true;
            anomali_bekleme_baslangic = su_an;
            queueBleCommand(0x0B);
            Serial.println("⚠️ [MUHTEMEL DEPREM] Etiket bekleniyor...");
            Serial.println("🖊️ [TEST] Serial'a yaz → 'deprem' veya 'noise' + Enter");
        } else if (anomali_seviyesi > 20.0 && gercek_sarsinti) {
            memcpy(anomali_features_kopyasi, features, sizeof(features));
            anomali_etiket_bekleniyor = true;
            anomali_bekleme_baslangic = su_an;
            queueBleCommand(0x0B);
            Serial.println("⚠️ [ANOMALİ] Etiket bekleniyor...");
            Serial.println("🖊️ [TEST] Serial'a yaz → 'deprem' veya 'noise' + Enter");
        }
    } else {
        if (su_an > deprem_kalkani_bitis) {
            deprem_kalkani_aktif = false;
            ledcWrite(BUZZER_PIN, 0);
        }
    }
}

// =========================================================================
// CORE 0: DEPREM + ENKAZ
// =========================================================================
void AiAndSensorTask(void* pvParameters) {
    vTaskDelay(500 / portTICK_PERIOD_MS); 
    if (xSemaphoreTake(i2c_mutex, portMAX_DELAY)) {
        Wire.beginTransmission(MPU_ADDR);
        Wire.write(0x75);
        Wire.endTransmission(true);
        Wire.requestFrom((uint8_t)MPU_ADDR, (uint8_t)1, (uint8_t)true);
        uint8_t whoami = Wire.read();
        Wire.beginTransmission(MPU_ADDR);
        Wire.write(0x6B);
        Wire.write(0x00);
        Wire.endTransmission(true);
        xSemaphoreGive(i2c_mutex);
    }
    vTaskDelay(100 / portTICK_PERIOD_MS);

    for (;;) {
        checkButton();

        if (calisma_modu == 0 || calisma_modu == 5) {
            if (calisma_modu == 0 && ilk_acilis) {
                Serial.println("Sistem hazır. Butona bas.");
                ilk_acilis = false;
            }
            if (calisma_modu == 5 && deprem_test_pending) {
                float freq  = (deprem_test_type == 2) ? 3.0f  : (deprem_test_type == 1) ? 5.0f : 0.0f;
                float amp   = (deprem_test_type == 2) ? 19.6f : (deprem_test_type == 1) ? 10.0f : 0.0f;
                for (int i = 0; i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; i++) {
                    float t = i * (EI_CLASSIFIER_INTERVAL_MS / 1000.0f);
                    if (deprem_test_type == 0) {
                        features[i] = 9.81f + ((rand() % 100) / 1000.0f); 
                    } else {
                        float sign = (sinf(2.0f * M_PI * freq * t) >= 0) ? 1.0f : -1.0f;
                        features[i] = amp * sign + ((rand() % 60) / 100.0f - 0.3f); 
                    }
                }
                deprem_test_pending = false;
                const char* tip_str = (deprem_test_type == 2) ? "GÜÇLÜ" : (deprem_test_type == 1) ? "HAFİF" : "NORMAL";
                Serial.printf("🧪 [TEST] Deprem sinyali üretildi: %s — sonuç:\n", tip_str);
                runDepremInference();
            }
            vTaskDelay(EI_CLASSIFIER_INTERVAL_MS / portTICK_PERIOD_MS);
            continue;
        }

        int16_t ax_raw = 0, ay_raw = 0, az_raw = 0;
        if (xSemaphoreTake(i2c_mutex, portMAX_DELAY)) {
            Wire.beginTransmission(MPU_ADDR);
            Wire.write(0x3B);
            Wire.endTransmission(true);
            int n = Wire.requestFrom((uint8_t)MPU_ADDR, (uint8_t)6, (uint8_t)true);
            if (n == 6) {
                ax_raw = Wire.read() << 8 | Wire.read();
                ay_raw = Wire.read() << 8 | Wire.read();
                az_raw = Wire.read() << 8 | Wire.read();
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
                runDepremInference();
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
                        queueBleCommand(0x0D);
                        
                        if (gercek_bir_deprem_yasandi_mi) {
                            if (!deviceConnected) {
                                sendLoRaBinary(0x04);
                                Serial.println("📡 [OTONOM] Telefon KOPUK! Ritmik vuruş doğrudan Karargaha fırlatıldı!");
                            } else {
                                Serial.println("ℹ️ [SİSTEM] Telefon bağlı. LoRa gönderimi uygulamaya bırakıldı.");
                            }
                        } else {
                            Serial.println("ℹ️ [SİSTEM] Vuruş algılandı ama deprem kaydı yok. İptal.");
                        }

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
        if (calisma_modu == 4) {
            if (!onceki_afet_modu) {
                bme.setGasHeater(0, 0);
                onceki_afet_modu = true;
                Serial.println("🔋 [AFET] BME680 kapatıldı.");
            }
            vTaskDelay(5000 / portTICK_PERIOD_MS);
            continue; 
        } else {
            if (onceki_afet_modu) {
                bme.setGasHeater(320, 150);
                onceki_afet_modu = false;
                Serial.println("🔥 [NORMAL] BME680 tekrar aktif.");
                vTaskDelay(2000 / portTICK_PERIOD_MS); 
            }
        }

        if (calisma_modu == 5) {
            if (yangin_test_pending) {
                if (xSemaphoreTake(fire_index_mutex, portMAX_DELAY)) {
                    for (int step = 0; step < 10; step++) {
                        float t = step / 9.0f;
                        int idx = step * 4;
                        fire_features[idx]     = 1.0f + (yangin_test_vals[0] - 1.0f) * t;
                        fire_features[idx + 1] = yangin_test_vals[1] * t;
                        fire_features[idx + 2] = yangin_test_vals[2] * t;
                        fire_features[idx + 3] = yangin_test_vals[3] * t;
                    }
                    fire_feature_index = FIRE_INPUT_SIZE;
                    xSemaphoreGive(fire_index_mutex);
                }
                if (!baseline_hazir) {
                    baseline_gas  = 50000.0f;
                    baseline_temp = 25.0f;
                    baseline_hum  = 50.0f;
                    baseline_pres = 1013.25f;
                    baseline_hazir = true;
                }
                yangin_test_pending = false;
                yanginInferenceRun(false, 0.0f, 0.0f, 0.0f, 0.0f);
            }
            vTaskDelay(500 / portTICK_PERIOD_MS);
            continue;
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
                Serial.printf("📡 [Baseline %d/%d] T=%.1f°C | Nem=%.1f%% | Gaz=%.1fkΩ | Basınç=%.1fhPa\n",
                    baseline_sayac + 1, BASELINE_SAMPLE_COUNT, temp, hum, gas, pres);
                bmeBaselineGuncelle(temp, hum, gas, pres);
            } else {
                Serial.printf("🌡️ T=%.1f°C | Nem=%.1f%% | Gaz=%.1fkΩ | Basınç=%.1fhPa\n",
                    temp, hum, gas, pres);
                yanginInference(temp, hum, gas, pres);
            }
        }
        vTaskDelay(5000 / portTICK_PERIOD_MS);
    }
}

// =========================================================================
// CORE 1: LORA ACK DİNLEYİCİ (KULAKLIK)
// =========================================================================
void LoRaAckTask(void* pvParameters) {
    for (;;) {
        if (Serial2.available()) {
            uint8_t b = Serial2.read();
            // Eğer gelen byte 0x06 (ACK) ise
            if (b == 0x06) {
                Serial.println("✅ [LORA RX] Karargahtan ACK (0x06) Alındı!");
                queueBleCommand(0x06); // BLE kuyruğuna at, telefona iletsin
            }
        }
        vTaskDelay(50 / portTICK_PERIOD_MS); 
    }
}

// =========================================================================
void setup() {
    Serial.begin(115200);
    Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2);

    fire_index_mutex = xSemaphoreCreateMutex();
    i2c_mutex = xSemaphoreCreateMutex();
    lora_mutex = xSemaphoreCreateMutex();
    ble_cmd_queue = xQueueCreate(10, sizeof(uint8_t));

    preferences.begin("rescuelink", true);
    wifi_ssid = preferences.getString("ssid", "");
    wifi_pass = preferences.getString("pass", "");
    preferences.end();
    if (wifi_ssid.length() > 0) {
        Serial.printf("✅ [WiFi] Kayıtlı ağ: %s\n", wifi_ssid.c_str());
        wifiConnect();
        if (WiFi.status() == WL_CONNECTED) {
            configTime(3 * 3600, 0, "pool.ntp.org", "time.nist.gov");
            Serial.println("⏱️ [NTP] Saat senkronizasyonu başlatıldı...");
            struct tm t;
            int deneme = 0;
            while (!getLocalTime(&t) && deneme < 10) {
                delay(500);
                deneme++;
            }
            if (getLocalTime(&t))
                Serial.printf("✅ [NTP] Saat: %02d:%02d:%02d\n", t.tm_hour, t.tm_min, t.tm_sec);
            else
                Serial.println("⚠️ [NTP] Saat alınamadı.");
        }
    }

    ledcAttach(BUZZER_PIN, frekans, cozunurluk);
    ledcWrite(BUZZER_PIN, 0);
    pinMode(BUTTON_PIN, INPUT_PULLUP);

    Wire.begin(I2C_SDA, I2C_SCL);
    delay(100);
    Wire.beginTransmission(MPU_ADDR); Wire.write(0x6B); Wire.write(0); Wire.endTransmission();

    tensor_arena = (uint8_t*)heap_caps_malloc(TENSOR_ARENA_SIZE, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (!tensor_arena) tensor_arena = (uint8_t*)ps_malloc(TENSOR_ARENA_SIZE);

    if (tensor_arena != nullptr) {
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
    } 

    BLEDevice::init("RescueLink_Node");
    BLEDevice::setMTU(512); 
    BLEServer* pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());
    BLEService* pService = pServer->createService(SERVICE_UUID);

    pTxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
    pTxCharacteristic->addDescriptor(new BLE2902());

    BLECharacteristic* pRxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
    pRxCharacteristic->setCallbacks(new MyRxCallbacks());

    pService->start();
    pServer->getAdvertising()->start();

    xTaskCreatePinnedToCore(AiAndSensorTask, "AiAndSensorTask", 16384, NULL, 1, NULL, 0);
    xTaskCreatePinnedToCore(FireSensorTask,  "FireSensorTask",  16384, NULL, 1, NULL, 1);
    xTaskCreatePinnedToCore(LoRaAckTask, "LoRaAckTask", 2048, NULL, 2, NULL, 1);

    Serial.printf("\n🚀 RESCUELINK V5.0 FINAL (DIRECT MODE) | Firmware: %s\n", FIRMWARE_VERSION);
}

// =========================================================================
void loop() {
    static unsigned long last_heartbeat = 0;
    static unsigned long last_ota_check = 0;
    static bool ilk_ota = true;
    static bool ilk_heartbeat_atildi = false; 

    {
        uint8_t pending_cmd;
        while (xQueueReceive(ble_cmd_queue, &pending_cmd, 0) == pdTRUE)
            sendBleCommand(pending_cmd);
    }

    if (wifi_baglan_istegi) {
        wifi_baglan_istegi = false;
        wifiConnect();
    }

    if (ota_baslat_istegi) {
        ota_baslat_istegi = false;
        
        Serial.println("🧹 [OTA PREP] Sensörler ve AI durduruluyor, RAM boşaltılıyor...");
        calisma_modu = 0; 
        yangin_alarm_aktif = false;
        ledcWrite(BUZZER_PIN, 0);
        
        if (tensor_arena != nullptr) {
            free(tensor_arena);
            tensor_arena = nullptr;
            Serial.println("🧹 [OTA PREP] TFLite Tensor Arena boşaltıldı (16KB).");
        }
        
        delay(500); 
        Serial.printf("🔍 [OTA PREP] Güncel Boş RAM: %d byte\n", esp_get_free_heap_size());

        if (Update.begin(ble_ota_toplam) || Update.begin(UPDATE_SIZE_UNKNOWN)) {
            ble_ota_aktif  = true;
            ble_ota_alindi = 0;
            Serial.printf("📲 [BLE OTA] Başladı — Beklenen: %d byte\n", ble_ota_toplam);
            sendBleCommand(0x20); 
        } else {
            Serial.printf("❌ [BLE OTA] Update.begin hatası! Boş RAM: %d\n", esp_get_free_heap_size());
            sendBleCommand(0x22);
        }
    }

    unsigned long heartbeat_bekleme_suresi = ilk_heartbeat_atildi ? 3600000 : 60000;

    if (millis() - last_heartbeat > heartbeat_bekleme_suresi) {
        last_heartbeat = millis();
        ilk_heartbeat_atildi = true;
        
        Serial.println("💓 [HEARTBEAT] Sistem durumu Karargaha bildiriliyor!");
        
        if (deviceConnected) {
            sendBleCommand(0x12); 
        }
        sendLoRaBinary(0x12);
    }

    if (ilk_ota && millis() > 30000) {
        ilk_ota = false;
        last_ota_check = millis();
        checkOTA();
    } else if (!ilk_ota && millis() - last_ota_check > 3600000) {
        last_ota_check = millis();
        checkOTA();
    }

    if (anomali_upload_hazir) {
        anomali_upload_hazir = false;
        sendToEdgeImpulse(anomali_upload_label);
    }

    if (Serial.available()) {
        String serial_input = Serial.readStringUntil('\n');
        serial_input.trim();

        if (serial_input.startsWith("WIFI|")) {
            int p1 = serial_input.indexOf('|');
            int p2 = serial_input.indexOf('|', p1 + 1);
            if (p1 > 0 && p2 > 0) {
                wifi_ssid = serial_input.substring(p1 + 1, p2);
                wifi_pass = serial_input.substring(p2 + 1);
                preferences.begin("rescuelink", false);
                preferences.putString("ssid", wifi_ssid);
                preferences.putString("pass", wifi_pass);
                preferences.end();
                Serial.printf("✅ [TEST] WiFi kaydedildi: %s — Bağlanılıyor...\n", wifi_ssid.c_str());
                wifiConnect();
            }
        } else if (serial_input == "sus" && calisma_modu == 5) {
            ledcWrite(BUZZER_PIN, 0);
            yangin_alarm_aktif = false;
            son_bildirim = 0;
            normal_sayac = 0;
            Serial.println("🔇 [TEST] Alarm susturuldu, test modunda devam.");
        } else if (serial_input.startsWith("BLETEST|") && calisma_modu == 5) {
            String hexStr = serial_input.substring(8);
            uint8_t val = (uint8_t)strtol(hexStr.c_str(), NULL, 16);
            sendBleCommand(val);
            Serial.printf("📡 [BLETEST] TX'e gönderildi: 0x%02X\n", val);
        } else if (serial_input.startsWith("BLETEST_TXT|") && calisma_modu == 5) {
            String hexStr = serial_input.substring(12);
            uint8_t val = (uint8_t)strtol(hexStr.c_str(), NULL, 16);
            const char* label = "BILINMEYEN";
            if      (val == 0x0A) label = "DEPREM_ALARM";
            else if (val == 0x0B) label = "MUHTEMEL_DEPREM";
            else if (val == 0x0C) label = "YANGIN_ALARM";
            else if (val == 0x10) label = "GAZ_KACAGI";
            else if (val == 0x11) label = "YUKSEK_SICAKLIK";
            else if (val == 0x0D) label = "RITMIK_VURUS";
            else if (val == 0x22) label = "OTA_HATA";
            else if (val == 0x23) label = "OTA_TAMAM";
            pTxCharacteristic->setValue((uint8_t*)label, strlen(label));
            pTxCharacteristic->notify();
            Serial.printf("📡 [BLETEST_TXT] TX'e gönderildi: %s (0x%02X)\n", label, val);
        } else if (serial_input.startsWith("YANGIN_TEST|")) {
            if (calisma_modu != 5) {
                Serial.println("❌ [TEST] Önce MOD 5'e geç (butona bas).");
            } else {
                int p1 = serial_input.indexOf('|');
                int p2 = serial_input.indexOf('|', p1 + 1);
                int p3 = serial_input.indexOf('|', p2 + 1);
                int p4 = serial_input.indexOf('|', p3 + 1);
                if (p1 > 0 && p2 > 0 && p3 > 0 && p4 > 0) {
                    yangin_test_vals[0] = serial_input.substring(p1 + 1, p2).toFloat();
                    yangin_test_vals[1] = serial_input.substring(p2 + 1, p3).toFloat();
                    yangin_test_vals[2] = serial_input.substring(p3 + 1, p4).toFloat();
                    yangin_test_vals[3] = serial_input.substring(p4 + 1).toFloat();
                    yangin_test_pending = true;
                    Serial.printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
                    Serial.printf("📥 Girdi: gas=%.2f temp=%.2f hum=%.2f pres=%.2f\n",
                        yangin_test_vals[0], yangin_test_vals[1], yangin_test_vals[2], yangin_test_vals[3]);
                } else {
                    Serial.println("❌ Format: YANGIN_TEST|gas_ratio|temp_delta|hum_delta|pres_delta");
                }
            }
        } else if (serial_input.startsWith("DEPREM_TEST|")) {
            if (calisma_modu != 5) {
                Serial.println("❌ [TEST] Önce MOD 5'e geç (butona bas).");
            } else {
                String tip = serial_input.substring(serial_input.indexOf('|') + 1);
                tip.toLowerCase();
                if (tip == "guclu") deprem_test_type = 2;
                else if (tip == "hafif") deprem_test_type = 1;
                else deprem_test_type = 0;
                deprem_test_pending = true;
                Serial.printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
                Serial.printf("📥 Girdi: DEPREM_TEST|%s\n", tip.c_str());
            }
        } else if (serial_input == "OTA") {
            checkOTA();
        } else if (anomali_etiket_bekleniyor && serial_input.length() > 0) {
            strncpy(anomali_upload_label, serial_input.c_str(), 31);
            anomali_etiket_bekleniyor = false;
            anomali_upload_hazir = true;
            Serial.printf("[TEST] Serial etiket alındı: '%s' → Edge Impulse'a gönderiliyor...\n", anomali_upload_label);
        }
    }

    if (anomali_etiket_bekleniyor && millis() - anomali_bekleme_baslangic > 300000) {
        anomali_etiket_bekleniyor = false;
        Serial.println("⏰ [LABEL] 5 dakika geçti, etiket iptal edildi.");
    }

    vTaskDelay(100 / portTICK_PERIOD_MS);
}
