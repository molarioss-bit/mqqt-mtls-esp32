#pragma once

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <time.h>

extern String ssid, password, broker_ip;  
extern String ca_crt, cert_key, cert_crt;

extern const int GMT, daysaving;               //we need to let the user choose there time zone, we can add that later
extern const char* ntp_server;        //we can get the right time using in inerlal clock, i dont have it right

extern PubSubClient esp_publish;



void connect();
void sync();
void connect_mqtt_server();





