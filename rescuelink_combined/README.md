🚀 RescueLink Edge Node - V4.1'den V4.6'ya Evrim ve Mimari Değişiklik Raporu
Bu rapor, projenin ilk stabil iskeleti olan V4.1 sürümü ile sahadaki zorlu afet senaryolarına tam uyumlu hale getirilen V4.6 (Final) sürümü arasındaki kritik mimari değişiklikleri, donanım optimizasyonlarını ve silinen/eklenen kod bloklarını detaylandırmaktadır.

1. 📡 Haberleşme ve Otonomi (LoRa & GPS)
İlk kodda cihaz yalnızca Bluetooth'a bağımlıydı ve merkeze giden veriler tanımsızdı. Yeni mimaride cihaz tamamen otonom bir "Hayatta Kalma Kapsülü"ne dönüştürüldü.

Offline GPS Hafızası (EKLENDİ): Global son_lat ve son_lon değişkenleri sisteme entegre edildi. Mobil uygulama (Flutter) cihaza bağlıyken güncel koordinatları sürekli ESP32'nin RAM'ine yazmaktadır. Telefon enkaz altında parçalansa bile ESP32, son bilinen koordinatlarını LoRa paketine gömerek merkeze iletir.

Binary LoRa Protokolü (DEĞİŞTİRİLDİ): Eski koddaki Serial2.println("ENKAZ|RITMIK_VURUS"); (ASCII String) formatı tamamen SİLİNDİ. Yerine AFAD sistemleriyle tam uyumlu 12-byte ham byte dizisi gönderen sendLoRaBinary() fonksiyonu EKLENDİ.

Varsayılan Kişi Sayısı (EKLENDİ): Otonom gönderimlerde (örneğin cihaz telefona ulaşamadan ritmik vuruş algıladığında), Karargahın enkazı "boş" sanmaması için paketin 11. byte'ı (packet[11] = 1;) "1 Kişi" olarak sabitlendi.

2. 🛡️ Çift Çekirdek Güvenliği (Dual-Core Thread Safety)
ESP32'nin asimetrik çift çekirdekli yapısında (Core 0 ve Core 1) yaşanan bellek ve donanım çakışmaları tamamen çözüldü.

UART (LoRa) Kilidi (EKLENDİ): lora_mutex semaphore objesi oluşturuldu. Deprem task'ı (Core 0) ritmik vuruş atarken, Yangın veya Heartbeat task'ı (Core 1) aynı anda LoRa üzerinden mesaj yollamaya çalışırsa sistemin çökmesi engellendi.

I2C Hat Koruması (DEĞİŞTİRİLDİ): MPU6050 sensöründen ivme verisi okunurken kullanılan çıplak I2C komutları, i2c_mutex ve Wire.endTransmission(false) güvenlik zırhlarıyla sarıldı. Sensör kilitlenmeleri (I2C Hang) sıfıra indirildi.

3. 🧠 Bellek Yönetimi ve BLE Optimizasyonu (Memory Allocation)
Mobil uygulamadan gelen paketlerin işlenmesinde yaşanan ve cihazı sağır bırakan ölümcül hatalar giderildi.

Null-Terminator (0x00) Zırhı (DEĞİŞTİRİLDİ): Eski sürümdeki String rxValue = pCharacteristic->getValue(); mantığı tamamen ÇÖPE ATILDI. Float (koordinat) verileri hex'e çevrildiğinde aralarda oluşan \0 karakterlerinin String'i bölmesini engellemek için, veriler getData() ve getLength() fonksiyonları ile doğrudan ham bellek (Raw Pointer / uint8_t*) seviyesinde okunmaya başlandı.

Sliding Window & Memmove (EKLENDİ): Yangın Yapay Zekası (yanginInference) için gereken 200 float'luk dizinin her tahminde sıfırlanıp 4 dakika beklemesi sorunu çözüldü. Eski verilerin kaydırılması için C++ donanım seviyesi hızlandırıcısı olan memmove kullanılarak mikrosaniyeler içinde Kayar Pencere (Sliding Window) mantığı kuruldu. Cihaz artık kesintisiz her 5 saniyede bir AI tahmini yapabiliyor.

4. 🔋 Güç Yönetimi ve Donanım Tasarrufu (Power & Hardware)
Enkaz altında (Koma Modu) batarya ömrünü maksimuma çıkarmak için radikal değişiklikler yapıldı.

BME680 Isıtıcı Uyutması (DEĞİŞTİRİLDİ): Eski kodda, Koma Modunda (Mod 4) BME680 gaz ısıtıcısı her döngüde yeniden tetikleniyordu. Sisteme onceki_koma_modu isimli bir state (durum) bayrağı EKLENDİ. Koma moduna geçildiğinde ısıtıcı sadece 1 kez kapatılıyor ve sensör derin uykuya alınarak devasa bir pil tasarrufu sağlanıyor.

AI Örnekleme Frekansı (DEĞİŞTİRİLDİ): AiAndSensorTask içindeki donanıma gömülü vTaskDelay(25) sabiti silindi. Yerine doğrudan Edge Impulse modelinden çekilen EI_CLASSIFIER_INTERVAL_MS değişkeni konuldu. Model artık kendi eğitim frekansına %100 senkronize çalışıyor.

5. 🌐 Sistem İzleme ve Kullanıcı Arayüzü (Telemetry & Heartbeat)
Cihazın dış dünyayla olan etkileşimi, kullanıcının ve Karargahın kör noktada kalmasını engelleyecek şekilde güncellendi.

Canlı Telemetri Akışı (EKLENDİ): BME680'den okunan anlık sıcaklık, nem, gaz ve basınç değerlerinin mobil uygulamadaki arayüzü beslemesi için, BLE üzerinden TEL|24.5|45|1012|35 formatında sürekli veri basan bir blok oluşturuldu.

Heartbeat / Yaşam Sinyali (EKLENDİ): loop() fonksiyonunun içerisine 1 Saatte Bir (3600000 ms) tetiklenen bir yaşam sinyali eklendi. Cihaz, hiçbir acil durum olmasa dahi Karargaha (LoRa) ve Telefona (BLE) 0x12 sinyali ve son konumunu atarak "Ben aktifim ve çalışıyorum" bilgisini iletiyor.

🗑️ Çıkarılan / Terk Edilen Yaklaşımlar (Deprecations)
Saf ASCII String tabanlı LoRa haberleşmesi terk edildi (Tamamen Binary mimariye geçildi).

Yangın modelinde "Dizi dolsun, tahmin etsin, sonra diziyi sıfırlasın" şeklindeki statik array yaklaşımı terk edildi.

Koma modunda BME680 sensörünün gereksiz I2C okumaları yapması iptal edildi.

Sonuç: Kod satır sayısı korunarak iç mimari tamamen baştan yazıldı. ESP32 donanımı artık; bellek sızıntılarına karşı korumalı, çift çekirdek mimarisini güvenle kullanan ve iletişim kopsa dahi otonom hayatta kalma kararları verebilen endüstriyel bir ürüne dönüşmüştür.