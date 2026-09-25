pragma SPARK_Mode (On);
with Sim_Flash;
with Store_Log;

--  Store_Log over the simulated flash.  A SPARK instance, so gnatprove
--  checks the generic's body.
package Sim_Store is new Store_Log
  (0, Sim_Flash.Read, Sim_Flash.Program, Sim_Flash.Erase);
