#pragma once



//===============variables===============
extern String ssid, password, broker_ip;
extern int port;

struct Sensor{     //we can add more config variables later
    String name;
    String type;
    int pin;
    String topic;
};


extern const int MAX_SENSORS;  
extern Sensor sensors[];
extern int sensorCount;



//=================functions==============
String readFile(const char* f);
bool loadConfiguration();

