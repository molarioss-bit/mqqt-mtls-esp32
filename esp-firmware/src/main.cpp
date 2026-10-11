#include <Arduino.h>
#include <LittleFS.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <time.h>

#include "network.h"
#include "files.h"
#include "readSensors.h"

// ---------- Values loaded from /config.txt ----------
String ssid, password, broker_ip;
int port = 8883;

const char* ntp_server = "pool.ntp.org";
const int GMT = 0;
const int daysaving = 0;

// ---------- Certificates loaded from LittleFS ----------
String ca_crt, esp_crt, esp_key;

// ---------- Sensors ----------
const int MAX_SENSORS = 5;
Sensor sensors[MAX_SENSORS];
int sensorCount = 0;

unsigned long last[MAX_SENSORS] = {0};

// ---------- TLS ----------
WiFiClientSecure esp_TLS;
PubSubClient esp_publish(esp_TLS);

void setup() {

  Serial.begin(115200);
  delay(2000);

  if (!LittleFS.begin(true)) {
    Serial.println("LittleFS mount failed");
    return;
  }

  if (!loadConfiguration()) {
    Serial.println("Config invalid or missing, check /config.txt");
    return;
  }

  ca_crt  = readFile("/ca.crt");
  esp_crt = readFile("/esp.crt");
  esp_key = readFile("/esp.key");

  ca_crt.trim();
  esp_crt.trim();
  esp_key.trim();

  if (ca_crt.length() == 0 || esp_crt.length() == 0 || esp_key.length() == 0) {
    Serial.println("Missing certificate file(s) in LittleFS");
    return;
  }


  //here you can setup the pin mode, we can include this in a function later.
  for (int i = 0; i < sensorCount; i++) {

    if (sensors[i].type == "digital")        pinMode(sensors[i].pin, INPUT);
    if (sensors[i].type == "analog")         pinMode(sensors[i].pin, INPUT);
    if (sensors[i].type == "button")         pinMode(sensors[i].pin, INPUT_PULLUP);
    if (sensors[i].type == "ldr")            pinMode(sensors[i].pin, INPUT_PULLDOWN);
    if (sensors[i].type == "ntc")            pinMode(sensors[i].pin, INPUT);
  }

  connect();
  sync();

  esp_TLS.setCACert(ca_crt.c_str());
  esp_TLS.setCertificate(esp_crt.c_str());
  esp_TLS.setPrivateKey(esp_key.c_str());

  esp_publish.setServer(broker_ip.c_str(), port);
  connect_mqtt_server();

  Serial.setDebugOutput(true);
}

void loop()
{

  if (WiFi.status() != WL_CONNECTED) connect();
  if (!esp_publish.connected()) connect_mqtt_server();
  esp_publish.loop();



  //I can optimize this for loop and make more functions, but the code took me too much time already, I'll do that later
  for(int i = 0; i < sensorCount; i++){

      if(millis() - last[i] > sensors[i].delay){

        esp_publish.publish(sensors[i].topic.c_str(), readSensors(sensors[i]).c_str());
        last[i] = millis();
      }
    }
  }

