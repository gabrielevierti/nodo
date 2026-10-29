// NODO Curtain sample - ESP32 + stepper driver (STEP/DIR), two normally-closed limit switches.
// Requires PubSubClient and ArduinoJson via Arduino IDE Library Manager.
// IMPORTANT: prototype only. Use a protected low-voltage power supply, driver and motor current limiting.
// Motor calibration is required before trusting positions; keep the mechanism attended during commissioning.
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

const char* WIFI_SSID="CHANGE_ME";
const char* WIFI_PASS="CHANGE_ME";
const char* MQTT_HOST="192.168.1.10";
const uint16_t MQTT_PORT=1883;
const char* MQTT_USER="nodo_device";
const char* MQTT_PASS="CHANGE_ME";
const char* DEVICE_ID="curtain-01";
const int PIN_STEP=25, PIN_DIR=26, PIN_ENABLE=27;
const int PIN_MIN=32, PIN_MAX=33; // NC endstops to GND, internal pull-ups
const long TRAVEL_STEPS=4800; // Calibrate manually for your mechanism
const unsigned long STEP_INTERVAL_US=1500;
const unsigned long MAX_MOTION_MS=20000;
WiFiClient wifi; PubSubClient mqtt(wifi);
long positionSteps=0, goalSteps=0;
bool calibrated=false, moving=false;
unsigned long lastStepUs=0, motionStartMs=0, lastStateMs=0, lastConnectMs=0;
String base;

void publishState() {
  if (!mqtt.connected()) return;
  JsonDocument doc;
  doc["position"]=(int)((100L*positionSteps)/TRAVEL_STEPS);
  doc["moving"]=moving;
  doc["calibrated"]=calibrated;
  char buf[192]; serializeJson(doc,buf,sizeof(buf));
  mqtt.publish((base+"/state").c_str(),buf,true);
}
void stopMotor(){moving=false;digitalWrite(PIN_ENABLE,HIGH);publishState();}
void onMessage(char* topic, byte* payload, unsigned int length){
  if(length>256)return;
  JsonDocument doc;
  if(deserializeJson(doc,payload,length))return;
  const char* command=doc["command"]|"";
  if(strcmp(command,"stop")==0){stopMotor();return;}
  if(strcmp(command,"set_position")!=0||!calibrated)return;
  int target=constrain(doc["position"].as<int>(),0,100);
  goalSteps=(TRAVEL_STEPS*(long)target)/100;
  moving=(goalSteps!=positionSteps);
  motionStartMs=millis();
  digitalWrite(PIN_ENABLE,moving?LOW:HIGH);
  publishState();
}
void connectMqtt(){
  if(millis()-lastConnectMs<3000)return;
  lastConnectMs=millis();
  String availability=base+"/availability";
  if(mqtt.connect(DEVICE_ID,MQTT_USER,MQTT_PASS,availability.c_str(),1,true,"offline")){
    mqtt.subscribe((base+"/set").c_str());
    mqtt.publish(availability.c_str(),"online",true);
    mqtt.publish((base+"/announce").c_str(),"{\"name\":\"Tende soggiorno\",\"room\":\"Soggiorno\",\"type\":\"cover\"}",true);
    publishState();
  }
}
void setup(){
  Serial.begin(115200);base=String("nodo/")+DEVICE_ID;
  pinMode(PIN_STEP,OUTPUT);pinMode(PIN_DIR,OUTPUT);pinMode(PIN_ENABLE,OUTPUT);
  pinMode(PIN_MIN,INPUT_PULLUP);pinMode(PIN_MAX,INPUT_PULLUP);
  digitalWrite(PIN_ENABLE,HIGH);
  // Calibration requires manually moving the curtain fully closed BEFORE device boot.
  // Set calibrated=true ONLY after verifying this against the physical endstop.
  if(digitalRead(PIN_MIN)==LOW){positionSteps=0;calibrated=true;}
  WiFi.mode(WIFI_STA);WiFi.begin(WIFI_SSID,WIFI_PASS);
  mqtt.setServer(MQTT_HOST,MQTT_PORT);mqtt.setCallback(onMessage);mqtt.setBufferSize(512);
}
void loop(){
  if(WiFi.status()==WL_CONNECTED){if(!mqtt.connected())connectMqtt();mqtt.loop();}
  if(!moving)return;
  if(millis()-motionStartMs>MAX_MOTION_MS){stopMotor();return;}
  int dir=(goalSteps>positionSteps)?1:-1;
  // NC limit switches: HIGH means open circuit / triggered / broken wire -> STOP.
  if((dir<0&&digitalRead(PIN_MIN)==HIGH)||(dir>0&&digitalRead(PIN_MAX)==HIGH)){
    if(dir<0){positionSteps=0;calibrated=true;}else{positionSteps=TRAVEL_STEPS;}
    stopMotor();return;
  }
  if(micros()-lastStepUs<STEP_INTERVAL_US)return;
  lastStepUs=micros();digitalWrite(PIN_DIR,dir>0?HIGH:LOW);
  digitalWrite(PIN_STEP,HIGH);delayMicroseconds(5);digitalWrite(PIN_STEP,LOW);
  positionSteps+=dir;
  if(positionSteps==goalSteps)stopMotor();
  else if(millis()-lastStateMs>350){lastStateMs=millis();publishState();}
}
