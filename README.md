Son güncellemeler
🚀 RescueLink v1.0.0 Sürüm Notları: "Hayatta Kalma Mimarisi" (Survival Architecture) Güncellemesi
Bu dev güncelleme ile RescueLink sisteminin Donanım (ESP32) ve Yazılım (Flutter) entegrasyonu tamamen baştan yazılarak "Sıfır Hata, Maksimum Enerji Tasarrufu ve Otonom Karar Verme" standartlarına ulaştırılmıştır.

🛠️ 1. Donanım (ESP32 Edge Node) Geliştirmeleri
4-Fazlı Otonom Durum Makinesi: Cihaz artık güce ve deprem durumuna göre 3 ana fazda (Normal, Batarya, Enkaz/Koma) kendi kendini yönetiyor.

Özel Z-Ekseni Yapay Zeka Modeli: Edge Impulse modeli optimize edildi. Artık sadece Z ekseninden gelen veriler işlenerek gereksiz hesaplama yükü ortadan kaldırıldı.

Özel K-Means Anomali Algoritması: Edge Impulse'ın ham anomali skoru, (ham_anomali + 1.2) * 25.0 özel formülüyle 0-100 arası bir yüzdeye çevrildi. Eşik değerleri Kusursuzlaştırıldı (Deprem: >%80, Anomali: >%45).

Ağ Spam Koruması (30 Saniyelik Kalkan): Gerçek bir deprem anında cihazın ağı boğmaması (Network Flooding) için, ilk %80 eşiği aşıldıktan sonra 30 saniyelik "Refrakter (Kalkan) Süresi" eklendi.

5-Tap Ritmik Vuruş (Enkaz Modu): Cihaz Faz 3'e (Enkaz Modu) girdiğinde pili korumak için AI kapatılıyor. Bunun yerine 5'li ritmik vuruş dinleyicisi devreye giriyor. Vuruş algılandığında (0x0D), telefondan çekilen son dinamik GPS konumu LoRa üzerinden AFAD ağına basılıyor.

Watchdog (Nöbetçi) Kalp Atışı: Cihaz bağlı olduğu sürece her 60 saniyede bir merkeze (Mobil Uygulamaya) 0x0E kalp atışı (Heartbeat) fırlatarak "Hayattayım" sinyali veriyor.

📱 2. Mobil Uygulama (Flutter) Geliştirmeleri
Sıfır Tolerans SOS Kilidi (Strict Lock): Amatör kullanımları ve sahte alarmları engellemek için SOS butonu varsayılan olarak KİLİTLİ (Gri) hale getirildi. Kilit SADECE donanımdan gelen Kesin Deprem (0x0A) sinyaliyle veya donanımın sorduğu Anomali (0x0B) sorusuna "Evet" denmesiyle kırılıyor.

Kullanıcı İnisiyatifi (Anomali Onayı): Donanım sarsıntıdan emin olamazsa (Anomali Modu), uygulama ekrana "Bu bir deprem miydi?" diyaloğunu çıkartarak inisiyatifi insana bırakıyor.

Haptik ve Görsel Geri Bildirimler: Ritmik vuruşlar algılandığında telefon maksimum güçte titriyor (heavyImpact) ve donanımın gücü kesildiğinde (0x0C) anında uyarı veriyor. UI üzerindeki tüm geliştirici (debug) yazıları temizlenerek Production (Üretim) kalitesine geçildi.

Donanım Sağlık Denetleyicisi (Watchdog UI): Eğer uygulamaya donanımdan 3 dakika (180 saniye) boyunca kalp atışı (0x0E) gelmezse, sistem bağlantıyı kopmuş sayıyor, ana ekrandaki ikonu kırmızıya çevirip "Donanım Erişilemez - Koruma Devre Dışı" uyarısı veriyor.

Kritik Batarya "Koma" Modu (<%15): Telefonun şarjı %15'in altına düştüğünde, ivmeölçere bağlı olan GPS uyanma mantığı tamamen iptal ediliyor. GPS derin uykuya alınarak telefonun "Son Nefes" süresi uzatılıyor. GPS, sadece otonom bir deprem sinyali (0x0A) veya SOS butonuna manuel basımla uyandırılıyor.


