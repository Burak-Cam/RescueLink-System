Son güncellemeler
🚀 RescueLink v1.8.0 Sürüm Notları: "Saha Zekası ve Kesintisiz İletişim" (Field Intelligence) Güncellemesi
Bu dev güncelleme ile RescueLink sisteminin Donanım (ESP32 V4.6) ve Yazılım (Flutter V1.8.0) entegrasyonu tamamen baştan yazılarak "Sıfır Hata, Maksimum Enerji Tasarrufu ve Kesintisiz İletişim" standartlarına ulaştırılmıştır.

🛠️ 1. Donanım (ESP32 Edge Node) Geliştirmeleri
LoRa Çakışma Kalkanı (Mutex): ESP32'nin çift çekirdekli yapısındaki yarış durumları (Race Condition) Mutex ile çözülerek otonom paketlerin Gateway'e %100 sağlıklı iletilmesi sağlandı.
Otonom Konum Hafızası: Uygulamadan gelen son GPS konumu RAM'e kaydediliyor. Telefon kopsa bile otonom Vuruş/Kalp Atışı paketleri boş koordinatla değil, son bilinen konumla AFAD'a gidiyor.
Sliding Window Fire AI: Yangın yapay zekasının tahmin süresi 4 dakikadan 5 saniyeye düşürüldü.
4-Fazlı Otonom Durum Makinesi: Cihaz artık güce ve deprem durumuna göre 3 ana fazda (Normal, Batarya, Enkaz/Koma) kendi kendini yönetiyor.
Özel Z-Ekseni Yapay Zeka Modeli: Edge Impulse modeli optimize edildi. Artık sadece Z ekseninden gelen veriler işlenerek gereksiz hesaplama yükü ortadan kaldırıldı.
Özel K-Means Anomali Algoritması: Edge Impulse'ın ham anomali skoru, (ham_anomali + 1.2) * 25.0 özel formülüyle 0-100 arası bir yüzdeye çevrildi. Eşik değerleri Kusursuzlaştırıldı (Deprem: >%80, Anomali: >%45).
Ağ Spam Koruması (30 Saniyelik Kalkan): Gerçek bir deprem anında cihazın ağı boğmaması (Network Flooding) için, ilk %80 eşiği aşıldıktan sonra 30 saniyelik "Refrakter (Kalkan) Süresi" eklendi.
5-Tap Ritmik Vuruş (Enkaz Modu): Cihaz Faz 3'e (Enkaz Modu) girdiğinde pili korumak için AI kapatılıyor. Bunun yerine 5'li ritmik vuruş dinleyicisi devreye giriyor. Vuruş algılandığında (0x0D), cihaz (0x04) Otonom paketini LoRa üzerinden doğrudan AFAD'a basar.

📱 2. Mobil Uygulama (Flutter) Geliştirmeleri
Background Push Notifications: Uygulama kapalıyken dahi Karargah onayları (ACK) ve çevresel tehlikeler ekranda sistem bildirimi olarak belirir.
Canlı Sensör Telemetrisi: Yangın/Gaz sahnelerinde BME680 (Sıcaklık, Nem, Basınç, Hava Kalitesi) verileri eş zamanlı okunur ve arayüzde gösterilir.
Memory Leak & CPU Koruması: StreamSubscription sızıntıları kapatılarak uygulamanın pili sömürmesi engellendi.
Sıfır Tolerans SOS Kilidi (Strict Lock): Amatör kullanımları ve sahte alarmları engellemek için SOS butonu varsayılan olarak KİLİTLİ (Gri) hale getirildi. Kilit SADECE donanımdan gelen Kesin Deprem (0x0A) sinyaliyle veya donanımın sorduğu Anomali (0x0B) sorusuna "Evet" denmesiyle kırılıyor. (Geliştirici Modunda bu kilit atlanabilir).
Kritik Çevresel Uyarılar (Dead Man's Switch): Yangın/Gaz algılandığında siren çalmak yerine titreyen sessiz bir bildirim düşer. 60 saniye içinde iptal edilmezse otonom SOS fırlatılır.
Donanım Sağlık Denetleyicisi (Watchdog UI): Eğer uygulamaya donanımdan 3 dakika (180 saniye) boyunca kalp atışı (0x12) gelmezse, sistem bağlantıyı kopmuş sayıyor, ana ekrandaki ikonu kırmızıya çevirip uyarı veriyor.

Kritik Batarya "Koma" Modu (<%15): Telefonun şarjı %15'in altına düştüğünde, ivmeölçere bağlı olan GPS uyanma mantığı tamamen iptal ediliyor. GPS derin uykuya alınarak telefonun "Son Nefes" süresi uzatılıyor. GPS, sadece otonom bir deprem sinyali (0x0A) veya SOS butonuna manuel basımla uyandırılıyor.


