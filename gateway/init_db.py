import sqlite3
import os

DB_YOLU = 'database/rescuelink.db'

def veritabanini_kur():
    os.makedirs('database', exist_ok=True)
    
    # Eski veritabanı dosyasını sil (Temiz sayfa açıyoruz)
    if os.path.exists(DB_YOLU):
        os.remove(DB_YOLU)
        print("🗑️ Eski veritabanı temizlendi.")
    
    conn = sqlite3.connect(DB_YOLU)
    cursor = conn.cursor()

    # 1. CİHAZLAR TABLOSU
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS cihazlar (
        node_id INTEGER PRIMARY KEY,
        isim TEXT,
        son_gorulme DATETIME DEFAULT (datetime('now', 'localtime'))
    )
    ''')

    # 2. ACİL DURUM LOGLARI TABLOSU (Sağlık durumu eklendi)
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS sos_loglari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_id INTEGER,
        olay_tipi TEXT,
        kisi_sayisi INTEGER,
        saglik_durumu TEXT,
        enlem REAL,
        boylam REAL,
        tarih_saat DATETIME DEFAULT (datetime('now', 'localtime'))
    )
    ''')

    # Temel cihazları sisteme tanıt
    cursor.execute("INSERT INTO cihazlar (node_id, isim) VALUES (1, 'Node-0x01')")
    cursor.execute("INSERT INTO cihazlar (node_id, isim) VALUES (2, 'Node-0x02')")

    conn.commit()
    conn.close()
    print("✅ Mükemmel! Veritabanı telemetrisiz, tamamen sade ve detaylı SOS yapısıyla kuruldu.")

if __name__ == '__main__':
    veritabanini_kur()
