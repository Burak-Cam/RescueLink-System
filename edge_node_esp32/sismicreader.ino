#include <Wire.h>

#define I2C_SDA 10
#define I2C_SCL 11
#define BUZZER_PIN 6 

// ADRES ARTIK 0x68!
const int MPU_ADDR = 0x68; 

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  // Hattı başlat
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000); 

  Serial.println("\n--- MUCİZE RADAR: VERİ ÇEKİMİ BAŞLIYOR ---");
  delay(1000);

  // 1. ADIM: 0x68'i Uyandır
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B); // Güç yönetimi register'ı
  Wire.write(0);    // Uyku modunu kapat
  byte hata = Wire.endTransmission();
  
  if (hata == 0) {
    Serial.println("✅ SENSÖR UYANDI! Veriler akıyor...");
  } else {
    Serial.print("❌ UYANDIRMA HATASI! Hata Kodu: ");
    Serial.println(hata);
  }
}

void loop() {
  // 2. ADIM: 0x68'den Veri Talep Et
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  
  if (Wire.endTransmission(false) != 0) {
    Serial.println("⚠️ İletişim koptu...");
    delay(500);
    return;
  }
  
  Wire.requestFrom(MPU_ADDR, 6, true);
  
  // 3. ADIM: Gelen Veriyi Oku
  if (Wire.available() == 6) {
    int16_t ax = Wire.read() << 8 | Wire.read();
    int16_t ay = Wire.read() << 8 | Wire.read();
    int16_t az = Wire.read() << 8 | Wire.read();
    
    // G'ye ve m/s2'ye çevir
    float x = (ax / 16384.0) * 9.81;
    float y = (ay / 16384.0) * 9.81;
    float z = (az / 16384.0) * 9.81;
    float total = sqrt(x*x + y*y + z*z);

    Serial.print("X: "); Serial.print(x, 2);
    Serial.print(" | Y: "); Serial.print(y, 2);
    Serial.print(" | Z: "); Serial.print(z, 2);
    Serial.print(" || TOPLAM GÜÇ: "); Serial.println(total, 2);

    if (total > 15.0) {
      Serial.println("🚨 DARBE ALGILANDI! 🚨");
      digitalWrite(BUZZER_PIN, HIGH);
      delay(200);
      digitalWrite(BUZZER_PIN, LOW);
    }
  }

  delay(100); 
}