# RescueLink — Sistem Mimarisi

Bu doküman, RescueLink afet iletişim sisteminin uçtan uca mimarisini, bileşenler
arası protokolleri ve temel tasarım kararlarını açıklar. Amaç; sahada internet ve
baz istasyonu altyapısı çöktüğünde dahi, afetzededen AFAD karargâhına ulaşan
kesintisiz ve düşük güç tüketimli bir acil durum kanalı kurmaktır.

---

## 1. Genel Bakış

RescueLink üç katmanlı bir sistemdir. Her katman tek başına ayakta kalabilir ve bir
üst katman erişilemese bile kendi sorumluluğunu otonom olarak sürdürür.

```
   [ Afetzede ]
        │  BLE 
        ▼
 ┌──────────────────┐        LoRa (16-byte ikili paket)        ┌──────────────────┐
 │   Mobil Uygulama │       ──────────────────────────────────►│     Gateway      │
 │   (Flutter)      │   ◄───────  ACK / HQ mesajları  ───────  │ (Raspberry Pi)   │
 │  GPS / konum / UI│                                          │  Flask + SQLite  │
 └──────────────────┘                                          └────────┬─────────┘
        ▲                                                               │ Socket.IO
        │ BLE (UART servisi)                                            ▼
 ┌──────────────────┐                                          ┌──────────────────┐
 │  Edge Node       │                                          │ Karargâh Haritası│
 │   (ESP32)        │                                          │   (Web arayüzü)  │
 │ Mobil Uygulama   │                                          └──────────────────┘
 └──────────────────┘
```

| Katman | Donanım | Yazılım | Sorumluluk |
|--------|---------|---------|------------|
| **Edge Node** | ESP32 (çift çekirdek) + BME680 + ivmeölçer + LoRa | Arduino/C++, FreeRTOS, Edge Impulse | Sensör okuma, cihazda AI, otonom SOS, LoRa iletim |
| **Gateway** | Raspberry Pi + LoRa alıcı | Python / Flask / SQLite / Socket.IO | Paket çözme, kayıt, canlı harita yayını |
| **Mobil** | Kullanıcının telefonu | Flutter (Dart) | GPS/konum, kişi & sağlık bilgisi, kullanıcı arayüzü, OTA |

### Neden üç katman?

- **Edge Node**, telefon ve internet olmadan da çalışmak zorundadır; çünkü
  afetzede baygın olabilir ya da telefonu ölmüş olabilir. Bu yüzden tüm kritik
  karar mantığı (deprem/yangın tespiti, otonom SOS) cihazın kendisindedir.
- **LoRa**, hücresel şebeke çökse bile kilometrelerce menzil ve düşük güç sağladığı
  için katmanlar arası uzun mesafe taşıyıcısı olarak seçilmiştir.
- **Mobil katman** yalnızca bir "zenginleştirici"dir: konum, kişi sayısı ve sağlık
  durumu ekler. Mobil kopsa bile Edge Node son bilinen konumla yayına devam eder.

---

## 2. Edge Node (ESP32) Mimarisi

### 2.1 Çoklu görev (FreeRTOS) yapısı

ESP32'nin çift çekirdeği, gerçek zamanlı sensör okumanın LoRa iletimi veya AI
çıkarımı tarafından bloke edilmemesi için ayrı görevlere bölünmüştür:

| Görev | İşlev |
|-------|-------|
| `AiAndSensorTask` | İvmeölçer akışı + deprem AI çıkarımı |
| `FireSensorTask`  | BME680 okuma + yangın/gaz AI çıkarımı |
| `LoRaAckTask`     | Gateway'den gelen ACK dinleme |
| `loop()`          | Buton, durum makinesi, BLE komut işleme |

Paylaşılan kaynaklar **mutex** ile korunur, böylece çift çekirdekteki yarış
durumları (race condition) engellenir:

- `lora_mutex` → LoRa seri portuna eşzamanlı yazımı engeller (paket bütünlüğü)
- `i2c_mutex` → I²C veri yolunu (sensörler) korur
- `fire_index_mutex` → yangın özellik tamponunun indeksini korur

### 2.2 Otonom durum makinesi (çalışma modları)

Cihaz, fiziksel bir buton ve güç/afet durumuna göre fazlar arasında geçer:

| Mod | Ad | Davranış |
|-----|----|----|
| 0 | Beklemede | Sensörler pasif izlemede |
| 1 | Deprem | İvmeölçer AI aktif |
| 2 | Yangın | BME680 AI aktif |
| 3 | Hibrit | Deprem + yangın birlikte |
| 4 | Afet | CPU 80 MHz'e düşürülür (güç tasarrufu) |
| 5 | Test | Geliştirici/saha testi |

Enerji yönetimi tasarımın merkezindedir: kritik modlarda CPU frekansı düşürülür,
"enkaz modunda" AI kapatılıp yerine düşük güçlü ritmik vuruş dinleyici devreye
girer, "koma modunda" ise GPS uyandırma mantığı tümden iptal edilerek pilin son
nefesi uzatılır.

### 2.3 Cihaz-içi (Edge) yapay zeka

- **Deprem modeli:** İvmeölçerin Z-ekseni verisi Edge Impulse modeline beslenir.
  Yalnızca Z ekseni işlenerek gereksiz hesaplama yükü kaldırılmıştır.
- **Yangın modeli:** BME680 (sıcaklık, nem, gaz, basınç) verisi ayrı bir modele
  beslenir; kayan pencere (sliding window) ile hızlı tahmin yapılır.
- **Anomali skoru:** Edge Impulse'ın ham anomali skoru
  `(ham_anomali + 1.2) * 25.0` formülüyle 0–100 arası bir yüzdeye normalize edilir.
  Eşikler: deprem `> %80`, anomali `> %45`.
- **Ağ taşkını koruması:** İlk eşik aşıldıktan sonra 30 sn'lik "refrakter
  (kalkan) süresi" ile gerçek deprem anında ağın boğulması engellenir.

AI'ın **cihazda** çalışmasının nedeni, tam da bu sistemin var olma sebebidir:
internet erişilemez olduğunda dahi karar verebilmek ve tespit gecikmesini en aza
indirmek.

### 2.4 Otonom konum hafızası

Mobil uygulamadan gelen son GPS konumu RAM'de tutulur (`son_lat`, `son_lon`).
Telefon koptuğunda bile otonom paketler boş koordinatla değil, son bilinen konumla
gönderilir.

---

## 3. İletişim Protokolleri

### 3.1 LoRa paketi (Edge Node → Gateway) — 16 bayt

Paket boyutu, LoRa'nın havada kalma süresini (airtime) ve çarpışma olasılığını
düşük tutmak için kasıtlı olarak küçük ve sabittir.

| Bayt | Alan | Açıklama |
|------|------|----------|
| 0 | Header | Sabit `0x01` — paket başlangıç imzası |
| 1 | Olay tipi | Acil durum kodu (aşağıdaki tablo) |
| 2 | Gönderen ID | Kaynak node kimliği |
| 3 | Hedef ID | Hedef (Gateway = `0x00`) |
| 4 | Sıra no | Tekrar/röle eleme için artan sayaç |
| 5 | TTL | Mesh atlama sınırı (Gateway uyumu için sabit 1) |
| 6–9 | Enlem | `float` (little-endian) |
| 10–13 | Boylam | `float` (little-endian) |
| 14 | Kişi sayısı | Mobil uygulamadan |
| 15 | Sağlık durumu | Mobil uygulamadan |

Gateway tarafı bu yapıyı `struct.unpack('<BBBBBBffBB', ...)` ile çözer ve paket
başını `0x01` imzasına göre senkronlar (kayan tampon + 2 sn sessizlikte temizleme).

#### Olay tipi kodları

| Kod | Anlam |
|-----|-------|
| `0x00` | Manuel SOS |
| `0x01` | Deprem algılandı |
| `0x02` | Yangın algılandı |
| `0x03` | Gaz alarmı |
| `0x04` | Enkaz / vuruş tespiti |
| `0x12` | Sistem normal (heartbeat) |

#### Sağlık durumu kodları

| Kod | Anlam |
|-----|-------|
| `0x00` | Sağlıklı / stabil |
| `0x01` | Hafif yaralı |
| `0x02` | Ağır yaralı |

### 3.2 Mesh röle (dedup)

Her node, gördüğü mesaj kimliklerini 10 elemanlık dairesel bir önbellekte
(`msg_cache`) tutar. Daha önce görülen bir paket tekrar geldiğinde yeniden
yayılmaz — bu, mesh ağında broadcast fırtınasını (broadcast storm) önler.

### 3.3 BLE protokolü (Edge Node ↔ Mobil)

Nordic UART benzeri bir GATT servisi kullanılır:

| Rol | UUID |
|-----|------|
| Servis | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX (mobil → ESP32) | `6E400002-...` |
| TX (ESP32 → mobil) | `6E400003-...` |

**Mobil → Edge Node** (metin komutları): `LOC|lat|lon` (konum), WiFi provizyon,
`0xF0`/`0x99` susturma, `0x55`/`0x56` koma modu aç/kapa.

**Edge Node → Mobil** (olay baytları ve metin):

| Kod | Olay |
|-----|------|
| `0x06` | ACK |
| `0x0A` | Kesin deprem (SOS kilidini kırar) |
| `0x0B` | Anomali sorusu (kullanıcı onayı ister) |
| `0x0C` | Yangın |
| `0x0D` | Ritmik vuruş algılandı (enkaz modu) |
| `0x0E` | Kötü hava kalitesi |
| `0x0F` | Yüksek nem |
| `0x10` | Gaz kaçağı |
| `0x11` | Kritik sıcaklık |
| `0x12` | Heartbeat |
| `0x13` | Konum isteği |
| `0x20`–`0x23` | OTA durum baytları (hazır / chunk ACK / hata / başarı) |

Metin tabanlı kanallar: `TEL|temp|hum|press|iaq` (canlı telemetri),
`ACK|...`, `HQ|...` (karargâh mesajı), `OTA_AVAIL|sürüm`.

### 3.4 Gateway → Web arayüzü

Gateway, çözdüğü her olayı SQLite'a (`cihazlar`, `sos_loglari` tabloları) yazar ve
Socket.IO ile bağlı web istemcilerine `yeni_veri` olayı yayınlar. Harita arayüzü
`/api/harita_verisi` ile her node'un son durumunu, `/api/node_detay/<id>` ile son
10 olay geçmişini çeker.

---

## 4. Dayanıklılık ve Sağlık Denetimi

### 4.1 Çift yönlü heartbeat

- **Edge Node → Mobil:** Cihaz periyodik `0x12` kalp atışı gönderir. Mobil 180 sn
  boyunca kalp atışı alamazsa bağlantıyı kopmuş sayar, arayüz ikonunu kırmızıya
  çevirir (watchdog UI).
- **Edge Node → Gateway:** Heartbeat paketleri de `0x12` olarak Gateway'e gider ve
  cihazın "son görülme" zamanını günceller.

### 4.2 Otomatik yeniden bağlanma

Mobil tarafta BLE kopması algılandığında, son bağlanılan cihazın MAC'ine
otomatik yeniden bağlanma döngüsü devreye girer. Foreground service, uygulama arka
plandayken bile bağlantının ve bildirimlerin yaşamasını sağlar.

### 4.3 Sıfır tolerans SOS kilidi

Sahte alarmları engellemek için SOS butonu varsayılan olarak kilitlidir. Kilit
yalnızca donanımdan gelen kesin deprem (`0x0A`) sinyaliyle ya da anomali sorusuna
(`0x0B`) kullanıcının "evet" demesiyle açılır.

---

## 5. OTA (Kablosuz Güncelleme)

İki yol desteklenir:

1. **Cloud OTA (WiFi):** Cihaz, GitHub deposunun (`Burak-Cam/RescueLink-System`)
   en güncel sürüm etiketini ArduinoJson ile kontrol eder, yeni `firmware.bin`'i
   indirip `Update` kütüphanesiyle flash'lar.
2. **BLE OTA:** Firmware mobil uygulamadan parça parça (chunk) gönderilir; her
   parça uygulama seviyesinde `0x21` ACK ile akış kontrolüne tabidir.

---

## 6. Güvenlik Notları

- **Gizli anahtarlar:** Edge Impulse API anahtarı gibi sırlar `secrets.h` içinde
  tutulur ve `.gitignore` ile depo dışında bırakılır. Depoya yalnızca
  `secrets.example.h` şablonu girer. (Bkz. `secrets.example.h`.)
- **WiFi provizyonu:** SSID/parola BLE üzerinden alınır ve `Preferences` (NVS) ile
  cihazda saklanır.
- **Anahtar rotasyonu:** Bir anahtar geçmişte depoda açıkta kaldıysa, koddan
  silmek yeterli değildir — ilgili serviste iptal edilip yenilenmelidir.

---

## 7. Dizin Yapısı

```
RescueLink-System/
├── rescuelink_combined/        # ESP32 firmware (Arduino/C++)
│   ├── rescuelink_combined.ino #   ana firmware
│   ├── fire_model_data.h       #   yangın AI modeli verisi
│   └── secrets.example.h       #   gizli anahtar şablonu
├── gateway/                    # Raspberry Pi karargâh (Python/Flask)
│   ├── app.py                  #   LoRa dinleyici + API + Socket.IO
│   ├── init_db.py              #   veritabanı şeması
│   └── templates/index.html    #   canlı harita arayüzü
└── mobile_app/                 # Flutter mobil uygulama
    └── lib/
        ├── main.dart           #   uygulama girişi + konum köprüsü
        ├── screens/            #   arayüz ekranları
        └── services/           #   BLE, GPS, harita, pil, OTA servisleri
```

---

## 8. Katkı Sağlayanlar

| Katkı | Kişi |
|-------|------|
| Sistem tasarımı & mimari | Semi Kağan Şahin |
| Gateway (Raspberry Pi / backend) | Cem Albal |
| Mobil uygulama (Flutter) | Burak Çam |
| Yapay zeka (Edge Impulse modelleri) | Kerem Arkaç |
| Edge Node (ESP32 firmware) | Tüm ekip |
