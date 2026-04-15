#include <Wire.h>
#include <math.h>
#include <RescueLink_Disaster_Ai_2.0_inferencing.h> 
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- PİNLER VE DONANIM ---
#define I2C_SDA 10
#define I2C_SCL 11
#define POWER_SENSE_PIN 4  
#define RXD2 18            
#define TXD2 17            

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

const int MPU_ADDR = 0x68;

enum SystemState {
    FAZ_1_NORMAL,      
    FAZ_2_BATARYA,     
    FAZ_3_ENKAZ_MODU   
};

volatile SystemState gecerli_durum = FAZ_1_NORMAL;

float features[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
int feature_index = 0;
bool deviceConnected = false;
String lastSavedSos = ""; 

unsigned long sonVurusZamani = 0;
int vurusSayaci = 0;

// --- YENİ EKLENEN KALKAN DEĞİŞKENLERİ ---
bool deprem_kalkani_aktif = false;
unsigned long deprem_kalkani_bitis = 0;

BLEServer *pServer = NULL;
BLECharacteristic * pTxCharacteristic;

void sendBleCommand(uint8_t command) {
    if (deviceConnected) {
        uint8_t cmd[1] = {command};
        pTxCharacteristic->setValue(cmd, 1);
        pTxCharacteristic->notify();
    }
}

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("📱 BLE Bağlandı!");
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("📱 BLE Koptu!");
      pServer->getAdvertising()->start(); 
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxData = pCharacteristic->getValue().c_str();
      if (rxData.length() > 0) {
        lastSavedSos = rxData;
        Serial.print("📱 -> 📡 LoRa Kasasına Yazıldı: "); Serial.println(lastSavedSos);
        
        if (gecerli_durum == FAZ_2_BATARYA) {
            gecerli_durum = FAZ_3_ENKAZ_MODU;
            Serial.println("⚠️ SOS Geldi. AI Kapatıldı, Enkaz Moduna Geçildi.");
        }
        Serial2.println(lastSavedSos); 
      }
    }
};

// =========================================================================
// 🧠 CORE 0: AI VE SENSÖR YÖNETİMİ 
// =========================================================================
void AiAndSensorTask( void * pvParameters ) {
  for(;;) {
    bool hasPower = digitalRead(POWER_SENSE_PIN);

    // --- GÜÇ KONTROLÜ ---
    if (!hasPower && gecerli_durum == FAZ_1_NORMAL) {
        gecerli_durum = FAZ_2_BATARYA;
        sendBleCommand(0x0C); 
        Serial.println("🔋 GÜÇ KAYBI: Batarya moduna geçildi.");
    } else if (hasPower && gecerli_durum == FAZ_2_BATARYA) {
        gecerli_durum = FAZ_1_NORMAL;
        Serial.println("⚡ GÜÇ GELDİ: Şebekeye dönüldü.");
    }

    // --- SADECE Z EKSENİ OKUNUYOR ---
    Wire.beginTransmission(MPU_ADDR); Wire.write(0x3F); Wire.endTransmission(false);
    Wire.requestFrom(MPU_ADDR, 2, true);
    int16_t az_raw = Wire.read() << 8 | Wire.read();
    float az_ms2 = (az_raw / 16384.0) * 9.81;

    // --- FAZ 1 VE 2: DEPREM AI ---
    if (gecerli_durum == FAZ_1_NORMAL || gecerli_durum == FAZ_2_BATARYA) {
        features[feature_index++] = az_ms2;
        
        if (feature_index >= EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE) {
            feature_index = 0;
            signal_t signal;
            numpy::signal_from_buffer(features, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, &signal);
            ei_impulse_result_t result = { 0 };
            
            if (run_classifier(&signal, &result, false) == EI_IMPULSE_OK) {
                
                float ai_sonucu = result.classification[0].value; 
                float ham_anomali = result.anomaly; 

                float anomali_seviyesi = (ham_anomali + 1.2) * 25.0;
                if (anomali_seviyesi < 0) anomali_seviyesi = 0;
                if (anomali_seviyesi > 100) anomali_seviyesi = 100;

                Serial.print("🧠 AI: Deprem=%"); Serial.print(ai_sonucu * 100, 0);
                Serial.print(" | Anomali=%"); Serial.println(anomali_seviyesi, 0);

                unsigned long su_an = millis();

                // --- 30 SANİYELİK DEPREM KALKANI KONTROLÜ ---
                if (deprem_kalkani_aktif) {
                    if (su_an > deprem_kalkani_bitis) {
                        deprem_kalkani_aktif = false; // Kalkanı indir
                        Serial.println("🟢 [BİLGİ] 30 Saniyelik Deprem Süreci Bitti. Normal dinlemeye dönülüyor.");
                    } else {
                        Serial.print("⏳ Deprem süreci devam ediyor... Kalkanın bitmesine: ");
                        Serial.print((deprem_kalkani_bitis - su_an) / 1000);
                        Serial.println(" sn");
                    }
                } 
                // KALKAN YOKSA NORMAL KARARLARI VER
                else {
                    // 1. ÖNCELİK: KESİN DEPREM (Eşik: 0.80)
                    if (ai_sonucu > 0.80) {
                        sendBleCommand(0x0A); 
                        Serial.println("🚨 [KARAR] DEPREM VAR! Kilidi Kırdı!");
                        
                        // Kalkanı Aktif Et!
                        deprem_kalkani_aktif = true;
                        deprem_kalkani_bitis = su_an + 30000; 
                        
                        if (gecerli_durum == FAZ_2_BATARYA) gecerli_durum = FAZ_3_ENKAZ_MODU;
                    } 
                    // 2. ÖNCELİK: ANOMALİ (Eşik: 45.0)
                    else if (anomali_seviyesi > 45.0) { 
                        sendBleCommand(0x0B); 
                        Serial.println("⚠️ [KARAR] ANOMALİ (Standart Dışı Hareket) -> Telefona Onay Soruluyor.");
                        
                        // Anomalide kalkanı kısa tut (5 saniye)
                        deprem_kalkani_aktif = true;
                        deprem_kalkani_bitis = su_an + 5000; 
                    }
                }
            } // <-- run_classifier kapanışı
        } // <-- feature_index kapanışı
    } 
    // --- FAZ 3: ENKAZ MODU (SADECE RİTMİK VURUŞ) ---
    else if (gecerli_durum == FAZ_3_ENKAZ_MODU) {
        float sarsinti_genligi = abs(az_ms2 - 9.81);
        if (sarsinti_genligi > 2.0) { 
            unsigned long su_an = millis();
            if (su_an - sonVurusZamani > 200) { 
                vurusSayaci++;
                sonVurusZamani = su_an;
                
                Serial.print("Vuruş: "); 
                Serial.println(vurusSayaci);
                
                if (vurusSayaci >= 5) {
                    sendBleCommand(0x0D); 
                    Serial.println("🎯 RİTMİK VURUŞ ALGILANDI! (5 Başarılı Vuruş)");
                    
                    String tappingPayload;
                    if (lastSavedSos.length() > 0) {
                        tappingPayload = lastSavedSos + "|RITMIK_VURUS";
                    } else {
                        tappingPayload = "KONUM_YOK|RITMIK_VURUS"; 
                    }
                    
                    Serial2.println(tappingPayload); 
                    vurusSayaci = 0; 
                }
            }
        }
        if (millis() - sonVurusZamani > 3000) vurusSayaci = 0;
        vTaskDelay(50 / portTICK_PERIOD_MS); 
    }
    
    vTaskDelay(1000 / EI_CLASSIFIER_FREQUENCY); 
  } // <-- for(;;) döngüsü kapanışı
} // <-- İŞTE SİLİNEN PARANTEZ BURADAYDI! (AiAndSensorTask kapanışı)

// =========================================================================
// 🚀 SETUP VE CORE 1 (LORA HABERLEŞME)
// =========================================================================
void setup() {
    Serial.begin(115200);
    Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2); 
    pinMode(POWER_SENSE_PIN, INPUT_PULLUP); 

    Wire.begin(I2C_SDA, I2C_SCL);
    Wire.setClock(100000); 
    Wire.beginTransmission(MPU_ADDR); Wire.write(0x6B); Wire.write(0); Wire.endTransmission();

    BLEDevice::init("RescueLink_Node");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());
    BLEService *pService = pServer->createService(SERVICE_UUID);
    pTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
    pTxCharacteristic->addDescriptor(new BLE2902());
    BLECharacteristic * pRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
    pRxCharacteristic->setCallbacks(new MyCallbacks());
    pService->start();
    pServer->getAdvertising()->start();

    xTaskCreatePinnedToCore(AiAndSensorTask, "AiAndSensorTask", 32768, NULL, 1, NULL, 0);
    Serial.println("\n🚀 RESCUELINK EDGE NODE DEVREDE!");
}

void loop() {
    if (Serial2.available()) {
        String loraMsg = Serial2.readStringUntil('\n');
        if (loraMsg.indexOf("DELIVERED_TO_HQ") != -1) {
            sendBleCommand(0x06); 
            Serial.println("✅ LoRa'dan ACK Alındı, Telefona iletildi.");
        }
    }
    vTaskDelay(50 / portTICK_PERIOD_MS); 
}