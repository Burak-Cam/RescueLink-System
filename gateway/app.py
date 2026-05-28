from flask import Flask, render_template, jsonify
from flask_socketio import SocketIO
import serial
import threading
import time
import struct
import sqlite3
import os
import sys

app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*")

SERIAL_PORT = '/dev/ttyAMA0'
BAUD_RATE   = 9600
GATEWAY_ID  = 0x00
PAKET_BOYUT = 16 
DB_YOLU     = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'database', 'rescuelink.db')

OLAY_TIPLERI = {
    0x00: "MANUEL SOS",
    0x01: "DEPREM ALGILANDI",
    0x02: "YANGIN ALGILANDI",
    0x03: "GAZ ALARMI",
    0x04: "ENKAZ / VURUS TESPITI",
    0x12: "SISTEM NORMAL"
}

SAGLIK_DURUMLARI = {
    0x00: "Sağlıklı / Stabil",
    0x01: "Hafif Yaralı",
    0x02: "Ağır Yaralı"
}

def olay_tipi_coz(kod):
    return OLAY_TIPLERI.get(kod, f"Bilinmeyen (0x{kod:02X})")

def saglik_durumu_coz(kod):
    return SAGLIK_DURUMLARI.get(kod, "Bilinmiyor")

def db_baglan():
    conn = sqlite3.connect(DB_YOLU)
    conn.row_factory = sqlite3.Row
    return conn

def db_cihaz_guncelle(node_id):
    try:
        conn = db_baglan()
        c = conn.cursor()
        c.execute("UPDATE cihazlar SET son_gorulme = datetime('now', 'localtime') WHERE node_id = ?", (node_id,))
        if c.rowcount == 0:
            c.execute("INSERT INTO cihazlar (node_id, isim) VALUES (?, ?)", (node_id, f"Node-0x{node_id:02X}"))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"❌ DB Cihaz Guncelleme Hatası: {e}")

def db_olay_kaydet(node_id, olay_tipi, kisi_sayisi, saglik_durumu, enlem, boylam):
    try:
        conn = db_baglan()
        c = conn.cursor()
        c.execute("""
            INSERT INTO sos_loglari (node_id, olay_tipi, kisi_sayisi, saglik_durumu, enlem, boylam)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (node_id, olay_tipi, kisi_sayisi, saglik_durumu, enlem, boylam))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"❌ DB SOS Kayıt Hatası: {e}")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/harita_verisi')
def harita_verisi():
    try:
        conn = db_baglan()
        c = conn.cursor()
        c.execute('''
            SELECT a.node_id, a.olay_tipi, a.kisi_sayisi, a.saglik_durumu, a.enlem, a.boylam, c.isim, c.son_gorulme
            FROM sos_loglari a
            JOIN cihazlar c ON a.node_id = c.node_id
            WHERE a.id IN (SELECT MAX(id) FROM sos_loglari GROUP BY node_id)
        ''')
        kayitlar = c.fetchall()
        conn.close()
        return jsonify([{
            'raw_id'     : k[0],
            'hex_id'     : f"0x{k[0]:02X}",
            'durum'      : k[1],
            'kisi'       : k[2],
            'saglik'     : k[3],
            'lat'        : k[4],
            'lon'        : k[5],
            'isim'       : k[6],
            'son_gorulme': k[7]
        } for k in kayitlar])
    except Exception as e:
        print(f"❌ API Harita Verisi Hatası: {e}")
        return jsonify([])

@app.route('/api/node_detay/<int:node_id>')
def node_detay_getir(node_id):
    try:
        conn = db_baglan()
        cursor = conn.cursor()
        cursor.execute('SELECT olay_tipi, kisi_sayisi, saglik_durumu, tarih_saat FROM sos_loglari WHERE node_id = ? ORDER BY id DESC LIMIT 10', (node_id,))
        log_kayitlar = cursor.fetchall()
        conn.close()
        
        veriler = {'loglar': []}
        for l in log_kayitlar:
            veriler['loglar'].append({
                'olay': l[0], 
                'kisi': l[1],
                'saglik': l[2],
                'saat': l[3].split(' ')[1]
            })
        return jsonify(veriler)
    except Exception as e:
        print(f"❌ API Node Detay Hatası: {e}")
        return jsonify({'loglar': []})

def paketi_isle(veri, ser):
    try:
        paket = struct.unpack('<BBBBBBffBB', veri)
    except Exception as e:
        return

    olay_kodu   = paket[1]
    gonderen_id = paket[2]
    hedef_id    = paket[3]
    enlem       = paket[6]
    boylam      = paket[7]
    kisi_sayisi = paket[8]
    saglik_kodu = paket[9]
    
    if hedef_id != GATEWAY_ID:
        return

    db_cihaz_guncelle(gonderen_id)
    durum_metni = olay_tipi_coz(olay_kodu)
    saglik_metni = saglik_durumu_coz(saglik_kodu)

    try:
        ser.write(bytes([0x06, 0x02])) 
        ser.flush()
    except:
        pass

    # 🌟 DÜZELTME: Heartbeat (0x12) geldiğinde artık Socket.IO ile arayüzü güncelliyoruz!
    if olay_kodu == 0x12:
        print(f"💚 [HEARTBEAT] Node-0x{gonderen_id:02X} (Kişi: {kisi_sayisi}, Durum: {saglik_metni})")
        db_olay_kaydet(gonderen_id, "SISTEM NORMAL", kisi_sayisi, saglik_metni, enlem, boylam)
        socketio.emit('yeni_veri', {'data': "yenile"}) # EKSİK OLAN KOD EKLENDİ
        return

    print(f"🚨 [SOS YAKALANDI] Tip: {durum_metni} | Lat:{enlem:.4f} Lon:{boylam:.4f} | Kişi: {kisi_sayisi} | Sağlık: {saglik_metni}")
    db_olay_kaydet(gonderen_id, durum_metni, kisi_sayisi, saglik_metni, enlem, boylam)
    socketio.emit('yeni_veri', {'data': "yenile"})

def read_from_port(ser):
    print("\n==================================================")
    print("   🎧 [LORA] 16-BYTE DİNLENİYOR (AKILLI TAMPON)")
    print("==================================================\n")
    buf = bytearray()
    while True:
        try:
            byte_okunan = ser.read(1)
            if byte_okunan:
                buf.extend(byte_okunan)
            else:
                # 🌟 DÜZELTME: 2 saniye sessizlik olursa yarım kalan bozuk paketi sil (Sağırlığı çözer)
                if len(buf) > 0:
                    buf.clear()

            while len(buf) > 0 and buf[0] != 0x01:
                buf.pop(0)

            if len(buf) >= PAKET_BOYUT:
                tam_paket = bytes(buf[:PAKET_BOYUT])
                paketi_isle(tam_paket, ser)
                del buf[:PAKET_BOYUT]
        except Exception as e:
            time.sleep(1)

if __name__ == '__main__':
    try:
        # TIMEOUT EKLENDİ (Eskiden timeout=None yazıyordu, onu 2.0 yap!)
        lora = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2.0) 
        print(f"✅ [SERIAL] {SERIAL_PORT} başarıyla açıldı ({BAUD_RATE} baud).")
        dinleme_thread = threading.Thread(target=read_from_port, args=(lora,))
        dinleme_thread.daemon = True
        dinleme_thread.start()
    except Exception as e:
        print(f"❌ [SERIAL] Port açılamadı: {e}")
        sys.exit(1)

    socketio.run(app, host='0.0.0.0', port=5000, allow_unsafe_werkzeug=True)
