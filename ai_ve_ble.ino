#include <Wire.h>
#include <math.h>
#include <RescueLink_Disaster_Ai_2.0_inferencing.h> 
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- PİNLER VE TANIMLAMALAR ---
#define I2C_SDA 10
#define I2C_SCL 11
#define LED_PIN 2    
#define BUZZER_PIN 6 
#define RXD2 18 // LoRa RX
#define TXD2 17 // LoRa TX

// --- BLE UUID TANIMLAMALARI ---
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

const int MPU_ADDR = 0x68;

// --- AI DEĞİŞKENLERİ ---
bool deprem_modu_aktif = false;
unsigned long deprem_modu_bitis = 0;
const unsigned long DEPREM_SURESI = 30000; 
float features[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
unsigned long next_sampling_tick;
int feature_index = 0;
float peak_accel = 0.0; 

// --- BLE DEĞİŞKENLERİ ---
BLEServer *pServer = NULL;
BLECharacteristic * pTxCharacteristic;
bool deviceConnected = false;

// --- BLE CALLBACKS (BAĞLANTI DURUMU) ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Telefon BLE ile baglandi!");
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Telefon BLE baglantisi koptu!");
      pServer->getAdvertising()->start(); 
    }
};

// --- BLE CALLBACKS (TELEFONDAN VERİ GELİNCE) ---
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      uint8_t* rxData = pCharacteristic->getData();
      size_t rxLength = pCharacteristic->getLength();
      if (rxLength > 0) {
        Serial.print("Telefondan Ham Paket Geldi, LoRa'ya firlatiliyor...");
        Serial2.write(rxData, rxLength);
      }
    }
};

void setup() {
    Serial.begin(115200);
    // LoRa Seri Portu
    Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2);

    // Pin Ayarları
    pinMode(LED_PIN, OUTPUT);
    pinMode(BUZZER_PIN, OUTPUT);

    // I2C ve MPU6050 Kurulumu
    Wire.begin(I2C_SDA, I2C_SCL);
    Wire.setClock(100000); 
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x6B); Wire.write(0); Wire.endTransmission();

    // BLE Kurulumu
    BLEDevice::init("AFET_NODE_1");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());
    BLEService *pService = pServer->createService(SERVICE_UUID);
    pTxCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID_TX,
                        BLECharacteristic::PROPERTY_NOTIFY
                      );
    pTxCharacteristic->addDescriptor(new BLE2902());
    BLECharacteristic * pRxCharacteristic = pService->createCharacteristic(
                         CHARACTERISTIC_UUID_RX,
                         BLECharacteristic::PROPERTY_WRITE
                       );
    pRxCharacteristic->setCallbacks(new MyCallbacks());
    pService->start();
    pServer->getAdvertising()->start();

    Serial.println("\n========================================");
    Serial.println("   RESCUELINK v2.4 + BLE/LoRa ACTIVE   ");
    Serial.println("========================================");
    
    next_sampling_tick = millis();
}

void loop() {
    unsigned long su_an = millis();

    // --- 1. ALARM YÖNETİMİ ---
    if (deprem_modu_aktif) {
        if (su_an < deprem_modu_bitis) {
            digitalWrite(LED_PIN, (millis() / 150) % 2);
            digitalWrite(BUZZER_PIN, (millis() / 300) % 2); 
        } else {
            deprem_modu_aktif = false;
            digitalWrite(LED_PIN, LOW); digitalWrite(BUZZER_PIN, LOW);
            Serial.println("\n>>> [AI] Alarm suresi bitti. Normale donuldu.");
        }
    }

    // --- 2. DEPREM AI ANALİZİ ---
    if (su_an >= next_sampling_tick) {
        next_sampling_tick += (1000 / EI_CLASSIFIER_FREQUENCY);
        Wire.beginTransmission(MPU_ADDR);
        Wire.write(0x3F); Wire.endTransmission(false);
        Wire.requestFrom(MPU_ADDR, 2, true);

        if (Wire.available() == 2) {
            int16_t az_raw = Wire.read() << 8 | Wire.read();
            float az_ms2 = (az_raw / 16384.0) * 9.81;
            features[feature_index++] = az_ms2;
            float sarsıntı_genligi = abs(az_ms2 - 9.81);
            if (sarsıntı_genligi > peak_accel) peak_accel = sarsıntı_genligi;
        }

        if (feature_index >= EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE) {
            feature_index = 0;
            signal_t signal;
            numpy::signal_from_buffer(features, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, &signal);
            ei_impulse_result_t result = { 0 };
            run_classifier(&signal, &result, false);

            float ai_sonucu = result.classification[0].value;
            float ham_anomali = result.anomaly;
            float anomali_seviyesi = (ham_anomali + 1.2) * 25.0;
            if (anomali_seviyesi < 0) anomali_seviyesi = 0;
            if (anomali_seviyesi > 100) anomali_seviyesi = 100;

            Serial.println("\n--- AI ANALIZ SONUCU ---");
            if (ai_sonucu > 0.80 || deprem_modu_aktif) {
                Serial.println("DURUM: 🚨 DEPREM VAR!");
                if (ai_sonucu > 0.80) {
                    deprem_modu_aktif = true;
                    deprem_modu_bitis = su_an + DEPREM_SURESI;
                }
            } else if (ai_sonucu > 0.50) {
                Serial.println("DURUM: ⚠️ DEPREM OLABİLİR");
            } else if (anomali_seviyesi > 45.0) {
                Serial.println("DURUM: 🔍 ANOMALİ");
            } else {
                Serial.println("DURUM: ✅ Normal");
            }
            peak_accel = 0.0; 
        }
    }

    // --- 3. LoRa & BLE İLETİŞİM YÖNETİMİ ---
    if (Serial2.available()) {
        // AI'yı bloklamamak için kısa bir okuma penceresi
        int len = Serial2.available();
        uint8_t buffer[len];
        Serial2.readBytes(buffer, len);

        Serial.print("[LoRa] Karargahtan veri geldi. HEX: ");
        for(int i=0; i<len; i++) { Serial.print(buffer[i], HEX); Serial.print(" "); }
        Serial.println();

        if (deviceConnected) {
            // ACK (0x06) Kontrolü
            if (len > 0 && buffer[0] == 0x06) {
                uint8_t ackPacket[1] = {0x06};
                pTxCharacteristic->setValue(ackPacket, 1);
                pTxCharacteristic->notify();
            }
            // Metin Mesajı Çözümleme
            if (len > 1) {
                String feedbackMsg = "";
                if (buffer[1] == 0x02) feedbackMsg = "[KARARGAH] Sesinizi duyduk. AFAD yolda!";
                else if (buffer[1] == 0x03) feedbackMsg = "[KARARGAH] Koordinat teyit edildi.";
                else feedbackMsg = "[KARARGAH] Bilinmeyen durum kodu.";

                pTxCharacteristic->setValue(feedbackMsg.c_str());
                pTxCharacteristic->notify();
            }
        }
    }
}