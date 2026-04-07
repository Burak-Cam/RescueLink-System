#include <BLEDevice.h>

#include <BLEServer.h>

#include <BLEUtils.h>

#include <BLE2902.h>



// ESP32-S3 ve LoRa Baglantilari

#define RXD2 18 

#define TXD2 17 



// Standart BLE UART UUID'leri

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"

#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"



BLEServer *pServer = NULL;

BLECharacteristic * pTxCharacteristic;

bool deviceConnected = false;



// Bluetooth Baglanti Durumu Kontrolu

class MyServerCallbacks: public BLEServerCallbacks {

    void onConnect(BLEServer* pServer) {

      deviceConnected = true;

      Serial.println("Telefon BLE ile baglandi!");

    };

    void onDisconnect(BLEServer* pServer) {

      deviceConnected = false;

      Serial.println("Telefon BLE baglantisi koptu!");

      pServer->getAdvertising()->start(); 

      Serial.print("Cihaz tekrar yayin yapmaya (Advertising) basladi!");

    }

};



// Telefondan (BLE'den) Veri Gelince Calisacak Fonksiyon

class MyCallbacks: public BLECharacteristicCallbacks {

    void onWrite(BLECharacteristic *pCharacteristic) {

      // String formatini iptal ettik. Veriyi ham byte (uint8_t) olarak aliyoruz!

      uint8_t* rxData = pCharacteristic->getData();

      size_t rxLength = pCharacteristic->getLength();



      if (rxLength > 0) {

        Serial.print("Telefondan Ham Paket Geldi, Boyut: ");

        Serial.print(rxLength);

        Serial.println(" byte. Havaya firlatiliyor...");

        

        // Zerre degisiklik yapmadan, enter eklemeden, dogrudan LoRa'ya yaz (write)

        Serial2.write(rxData, rxLength); 

      }

    }

};



void setup() {

  Serial.begin(115200);

  Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2); // LoRa baslatildi



  // BLE Kurulumu

  BLEDevice::init("AFET_NODE_1"); // Telefondan bu ismi goreceksin

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

  Serial.println("BLE Aktif! Telefondan 'AFET_NODE_1' cihazina baglanin.");

}



void loop() {

  if (Serial2.available()) {

    

    delay(100); // 9600 baud bekleme kilidi (Mesajin tamamini almak icin)

    

    int len = Serial2.available();

    uint8_t buffer[len];

    Serial2.readBytes(buffer, len);



    Serial.print("Karargahtan Ham Hex Geldi: ");

    for(int i=0; i<len; i++) {

      Serial.print(buffer[i], HEX); Serial.print(" ");

    }

    Serial.println();



    if (deviceConnected) {

      

      // 1. HAMLE: Gelen paketin ilk byte'i 0x06 ise, telefonu YESIL yapmak icin firlat

      if (len > 0 && buffer[0] == 0x06) {

        uint8_t ackPacket[1] = {0x06};

        pTxCharacteristic->setValue(ackPacket, 1);

        pTxCharacteristic->notify();

        Serial.println("-> 1. Hamle: Telefona ACK (0x06) firlatildi.");

        

        delay(100); // Bluetooth'un nefes almasi ve ikinci mesaja hazirlanmasi icin kisa mola

      }



      // 2. HAMLE: Gelen paketin ikinci byte'i varsa, SIFREYI METNE CEVIR

      if (len > 1) {

        String feedbackMsg = "";

        

        // Sifre Sozlugu (Ileride 0x03, 0x04 diye yeni mesajlar da ekleyebilirsin)

        if (buffer[1] == 0x02) {

          feedbackMsg = "[KARARGAH] Sesinizi duyduk. AFAD ekipleri yola cikti!";

        } else if (buffer[1] == 0x03) {

          feedbackMsg = "[KARARGAH] Koordinat teyit edildi, lutfen bekleyin.";

        } else {

          feedbackMsg = "[KARARGAH] Bilinmeyen durum kodu alindi.";

        }



        // Cevrilen metni telefona (BLE) firlat

        pTxCharacteristic->setValue(feedbackMsg.c_str());

        pTxCharacteristic->notify();

        Serial.println("-> 2. Hamle: Telefona Metin firlatildi: " + feedbackMsg);

      }

    }

  }

}