/* NODO M1 BLE switch — ESP32-S3 / Arduino ESP32 core 3.x
 * Demo pin defaults to GPIO 2; change OUTPUT_PIN to a safe GPIO for your board.
 * Do NOT connect mains voltage or motors directly to the ESP32.
 * Library: ESP32 BLE Arduino (included with Espressif Arduino-ESP32 core).
 */
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

static const int OUTPUT_PIN = 2;
static const char* SERVICE = "B99E0001-3C1B-48F0-9F14-7B0401600001";
static const char* MANIFEST = "B99E0002-3C1B-48F0-9F14-7B0401600001";
static const char* STATE = "B99E0003-3C1B-48F0-9F14-7B0401600001";
static const char* COMMAND = "B99E0004-3C1B-48F0-9F14-7B0401600001";
static BLECharacteristic* stateChar = nullptr;
static bool outputOn = false;
static bool centralConnected = false;

static void publishState() {
  String payload = String("{\"value\":") + (outputOn ? "1" : "0") + "}";
  stateChar->setValue(payload.c_str());
  if (centralConnected) stateChar->notify();
}
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { centralConnected = true; }
  void onDisconnect(BLEServer*) override {
    centralConnected = false;
    BLEDevice::startAdvertising();
  }
};
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String payload = String(characteristic->getValue().c_str());
    // Accept only NODO M1 command format and strictly bounded numeric switch state.
    if (payload.length() > 100 || payload.indexOf("\"command\":\"set_power\"") < 0) return;
    int position = payload.indexOf("\"value\":");
    if (position < 0) return;
    String raw = payload.substring(position + 8);
    raw.trim();
    char* end = nullptr;
    double numeric = strtod(raw.c_str(), &end);
    while (*end == ' ' || *end == '\t') ++end;
    if (*end != '}' || (numeric != 0.0 && numeric != 1.0)) return;
    outputOn = numeric == 1.0;
    digitalWrite(OUTPUT_PIN, outputOn ? HIGH : LOW);
    publishState();
  }
};
void setup() {
  Serial.begin(115200);
  pinMode(OUTPUT_PIN, OUTPUT);
  digitalWrite(OUTPUT_PIN, LOW);
  BLEDevice::init("NODO ESP32 Demo");
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService* service = server->createService(SERVICE);
  auto* manifest = service->createCharacteristic(MANIFEST, BLECharacteristic::PROPERTY_READ);
  manifest->setValue("{\"protocol\":\"nodo/1\",\"name\":\"ESP32 Demo LED\",\"kind\":\"switch\"}");
  stateChar = service->createCharacteristic(STATE, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  stateChar->addDescriptor(new BLE2902());
  auto* command = service->createCharacteristic(COMMAND, BLECharacteristic::PROPERTY_WRITE);
  command->setCallbacks(new CommandCallbacks());
  publishState();
  service->start();
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("NODO M1 BLE switch advertising");
}
void loop() { delay(100); }
