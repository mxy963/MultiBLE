#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include <ZMPT101B.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// BLE Ayarları
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Global Değişkenler
String blePayload = "";
float resistance = 0.0;
float highVoltage = 0.0, lowVoltage = 0.0;
float acVoltage = 0.0;
float current = 0.0;
int continuityState = 0;

// Donanım Pinleri
const int buttonPin = 2;
int currentMode = 0;
const int NUM_MODES = 6;

// Kontinüite Testi
const int CONTINUITY_TEST_PIN = 26;
const int BUZZER_PIN = 25;

// Direnç Ölçümü
const int RESISTANCE_PIN = 33;
const float REFERENCE_RESISTOR = 120000.0;

// DC Voltaj
const int HIGH_VOLTAGE_PIN = 34;
const int LOW_VOLTAGE_PIN = 35;
const float ADC_MAX = 4095.0;
const float V_REF = 3.3;
float highVoltageReadings[10] = {0};
float lowVoltageReadings[10] = {0};
int voltageIndex = 0;

// Akım Ölçümü
const int CURRENT_SENSOR_PIN = 36;
float zeroOffsetCurrent = 0;
const int NUM_CURRENT_SAMPLES = 50;
const float MV_PER_AMP = 0.066;
float currentReadings[10] = {0};
int currentIndex = 0;

// AC Voltaj
ZMPT101B voltageSensor(32, 50.0);
float zeroOffsetAC = 0;

// BLE Callback Sınıfı
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Cihaz bağlandı!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Cihaz bağlantısı kesildi!");
    }
};

void setup() {
  Serial.begin(115200);
  
  pinMode(buttonPin, INPUT_PULLUP);
  pinMode(CONTINUITY_TEST_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RESISTANCE_PIN, INPUT);
  pinMode(CURRENT_SENSOR_PIN, INPUT);

  Wire.begin();
  if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED baslatilamadi!");
    while(1);
  }
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  calibrateCurrentSensor();
  calibrateACSensor();

  BLEDevice::init("ESP32-Multimeter");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->start();

  display.setTextSize(1);
  display.setCursor(0,0);
  display.println("BLE Multimetre Hazir");
  display.display();
  delay(2000);
}

void loop() {
  if(digitalRead(buttonPin) == LOW) {
    currentMode = (currentMode + 1) % NUM_MODES;
    delay(300);
  }

  display.clearDisplay();
  blePayload = "";
  
  switch(currentMode) {
    case 0: 
      displayHello();
      blePayload = "MODE:0";
      break;
      
    case 1: 
      measureContinuity();
      blePayload = "CONT:" + String(continuityState);
      break;
      
    case 2: 
      measureResistance();
      blePayload = "RES:" + String(resistance);
      break;
      
    case 3: 
      measureDCVoltage();
      blePayload = "DCV:" + String(highVoltage, 2) + "," + String(lowVoltage, 2);
      break;
      
    case 4: 
      measureACVoltage();
      blePayload = "ACV:" + String(acVoltage, 2);
      break;
      
    case 5: 
      measureCurrent();
      blePayload = "CUR:" + String(current, 3);
      break;
  }
  display.display();

  if(deviceConnected) {
    pCharacteristic->setValue(blePayload.c_str());
    pCharacteristic->notify();
    delay(10); // Veri gönderim hızını optimize et
  }

  if(!deviceConnected && oldDeviceConnected) {
    pServer->startAdvertising();
    oldDeviceConnected = deviceConnected;
  }
  if(deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }
}

// Ölçüm Fonksiyonları ---------------------------------------------------------
void displayHello() {
  display.setCursor(0, 0);
  display.setTextSize(1);
  display.println("BLE Multimetre Aktif");
}

void measureContinuity() {
  int raw = digitalRead(CONTINUITY_TEST_PIN);
  if (raw == HIGH) {
    tone(BUZZER_PIN, 1000, 200);
    display.setCursor(0, 0);
    display.setTextSize(1);
    display.println("iletkenlik: Var");
    continuityState = 1;
  } else {
    noTone(BUZZER_PIN);
    display.setCursor(0, 0);
    display.setTextSize(1);
    display.println("iletkenlik: Yok");
    continuityState = 0;
  }
}

void measureResistance() {
  int raw = analogRead(RESISTANCE_PIN);
  float voltage = (raw / ADC_MAX) * V_REF;

  if (voltage > 0) {
    resistance = (REFERENCE_RESISTOR * (V_REF - voltage)) / voltage;
    
    display.setCursor(0, 0);
    display.setTextSize(1);
    display.println("Direnc:");
    display.setTextSize(2);

    if (resistance >= 1000) {
      display.printf("%.2f kΩ", resistance / 1000);
    } else {
      display.printf("%.2f Ω", resistance);
    }
  } else {
    display.setCursor(0, 0);
    display.setTextSize(1);
    display.println("Direnc:");
    display.setTextSize(2);
    display.println("Sonsuz");
  }
}

void measureDCVoltage() {
  int high_raw = analogRead(HIGH_VOLTAGE_PIN);
  highVoltage = (high_raw / ADC_MAX) * V_REF * 121.5;
  
  int low_raw = analogRead(LOW_VOLTAGE_PIN);
  lowVoltage = (low_raw / ADC_MAX) * V_REF * 16;

  highVoltageReadings[voltageIndex] = highVoltage;
  lowVoltageReadings[voltageIndex] = lowVoltage;
  voltageIndex = (voltageIndex + 1) % 10;

  float avgHigh = 0, avgLow = 0;
  for (int i = 0; i < 10; i++) {
    avgHigh += highVoltageReadings[i];
    avgLow += lowVoltageReadings[i];
  }
  highVoltage = avgHigh / 10;
  lowVoltage = avgLow / 10;

  display.setCursor(0, 0);
  display.setTextSize(1);
  display.println("DC Voltaj:");
  display.setTextSize(2);
  display.printf("Yuksek: %.2f V", highVoltage);
  display.setCursor(0, 40);
  display.printf("Dusuk: %.2f V", lowVoltage);
}

void measureACVoltage() {
  acVoltage = voltageSensor.getRmsVoltage() - zeroOffsetAC;

  // Çok küçük veya negatif dalgalanmaları sıfırlamak için eşik değeri ekleniyor
  if (acVoltage < 18.05) {
    acVoltage = 0.0;
  }

  display.setCursor(0, 0);
  display.setTextSize(1);
  display.println("AC Voltaj:");
  display.setTextSize(2);
  display.printf("%.2f V", acVoltage);
}

void measureCurrent() {
  long sum = 0;
  for (int i = 0; i < NUM_CURRENT_SAMPLES; i++) {
    sum += analogRead(CURRENT_SENSOR_PIN);
    delay(2);
  }
  float voltage = (sum / NUM_CURRENT_SAMPLES / ADC_MAX) * V_REF;
  current = (voltage - zeroOffsetCurrent) / MV_PER_AMP;

  currentReadings[currentIndex] = current;
  currentIndex = (currentIndex + 1) % 10;

  float avgCurrent = 0;
  for (int i = 0; i < 10; i++) {
    avgCurrent += currentReadings[i];
  }
  current = avgCurrent / 10;

  display.setCursor(0, 0);
  display.setTextSize(1);
  display.println("Akim:");
  display.setTextSize(2);
  display.printf("%.3f A", current);
}

void calibrateCurrentSensor() {
  long sum = 0;
  for (int i = 0; i < NUM_CURRENT_SAMPLES; i++) {
    sum += analogRead(CURRENT_SENSOR_PIN);
    delay(2);
  }
  zeroOffsetCurrent = (sum / NUM_CURRENT_SAMPLES / ADC_MAX) * V_REF;
}

void calibrateACSensor() {
  float sum = 0;
  
  // İlk 10 ölçümün ortalamasını alarak sıfır noktası belirle
  for (int i = 0; i < 10; i++) {
    sum += voltageSensor.getRmsVoltage();
    delay(150); // Ölçümler arasında küçük bir gecikme
  }
  zeroOffsetAC = sum / 10; // Ortalama sıfır değeri olarak ayarlanır
}