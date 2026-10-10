#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <time.h>
#include "network.h"



// ---------- Connection functions ----------
void connect() {
  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid.c_str(), password.c_str());

  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(500);
  }
  Serial.println("\nConnected to WiFi");
}

void sync() {
  Serial.println("Syncing time...");
  configTime(GMT, daysaving, ntp_server);

  while (time(nullptr) < 100000) {
    Serial.print(".");
    delay(500);
  }
  Serial.println("\nSynced successfully");
}

void connect_mqtt_server() {
  Serial.println("Connecting to MQTT server...");

  while (!esp_publish.connected()) {
    if (!esp_publish.connect("esp32")) {
      Serial.printf("Failed, state = %d, retrying in 2s\n", esp_publish.state());
      delay(2000);
    }
  }
  Serial.println("Connected to MQTT broker");
}