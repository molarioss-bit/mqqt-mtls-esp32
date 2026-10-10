#include <LittleFS.h>
#include "files.h"   // was "network.h" — fixed

String readFile(const char* path) {
  File f = LittleFS.open(path, "r");
  if (!f) {
    Serial.printf("Could not open %s\n", path);
    return "";
  }
  String content = f.readString();
  f.close();
  return content;
}

bool loadConfiguration() {
  File file = LittleFS.open("/config.txt", "r");
  if (!file) {
    Serial.println("Could not open /config.txt");
    return false;
  }

  while (file.available()) {
    String line = file.readStringUntil('\n');
    line.trim();

    if (line.startsWith("ssid="))          ssid = line.substring(5);
    else if (line.startsWith("password=")) password = line.substring(9);
    else if (line.startsWith("broker="))   broker_ip = line.substring(7);   
    else if (line.startsWith("port="))     port = line.substring(5).toInt();
    else if (line.startsWith("sensor=") && sensorCount < MAX_SENSORS) {
      String data = line.substring(7);

      int c1 = data.indexOf(',');
      int c2 = data.indexOf(',', c1 + 1);
      int c3 = data.indexOf(',', c2 + 1);

      sensors[sensorCount].name  = data.substring(0, c1);
      sensors[sensorCount].type  = data.substring(c1 + 1, c2);
      sensors[sensorCount].pin   = data.substring(c2 + 1, c3).toInt();
      sensors[sensorCount].topic = data.substring(c3 + 1);

       sensors[sensorCount].topic.trim();
      sensorCount++;
    }
  }
  file.close();

  broker_ip.trim();
  return ssid.length() > 0 && broker_ip.length() > 0;
}