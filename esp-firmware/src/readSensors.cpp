#include <Arduino.h>

#include "readSensors.h"
#include "files.h"


//here we include the support of the sensors, we have now the normal digital, normal analog, light sensor, temp sensor.
//we will setup the pins in the setup()
//maybe i include support of other sensors like IR 


String readSensors(const Sensor &s) {

  if (s.type == "analog")  return String(analogRead(s.pin));
  if (s.type == "digital") return String(digitalRead(s.pin));
  if (s.type == "button") return String(digitalRead(s.pin));

  if (s.type == "ldr") {
    int raw = analogRead(s.pin);
    return String(map(raw, 0, 4095, 0, 100));   // light level in %
  }

  if (s.type == "ntc") {
    int raw = analogRead(s.pin);
    if (raw >= 4095) return "error";
    
    float r = 10000.0 * raw / (4095.0 - raw);
    float t = 1.0 / (log(r / 10000.0) / 3950.0 + 1.0 / 298.15) - 273.15;
    return String(t);
  }
  return "unknown type";
}
