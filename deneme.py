import serial
import threading
import sys
import time

# Raspberry Pi için genellikle varsayılan seri port /dev/serial0'dır.
SERIAL_PORT = '/dev/ttyAMA0'
BAUD_RATE = 9600

try:
    lora = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
except Exception as e:
    print(f"Seri port açılamadı! Hata: {e}")
    sys.exit(1)

def receive_messages():
    """Arka planda sürekli LoRa'dan gelen verileri dinler."""
    while True:
        if lora.in_waiting > 0:
            try:
                # Gelen veriyi oku ve decode et
                incoming = lora.readline().decode('utf-8').strip()
                if incoming:
                    # Gelen veriyi ekrana yaz, sonra tekrar girdi imlecini (>) koy
                    print(f"\r[ESP32'den Gelen] -> {incoming}\n> ", end="", flush=True)
            except UnicodeDecodeError:
                pass # Bozuk byte gelirse yoksay
        time.sleep(0.01) # İşlemciyi yormamak için ufak bir bekleme

print("Raspberry Pi 5 LoRa Terminaline Hoş Geldiniz.")
print("Mesajınızı yazıp Enter'a basın. Çıkmak için Ctrl+C.")
print("> ", end="", flush=True)

# Dinleme işlemini arka planda başlat
rx_thread = threading.Thread(target=receive_messages, daemon=True)
rx_thread.start()

try:
    # Ana döngü terminalden (senden) girdi bekler
    while True:
        msg_out = input()
        if msg_out.strip():
            # Mesajı yolla (sonuna satır sonu karakteri ekleyerek)
            lora.write((msg_out + '\n').encode('utf-8'))
            print("> ", end="", flush=True)
except KeyboardInterrupt:
    print("\nÇıkış yapılıyor...")
    lora.close()
    sys.exit(0)
