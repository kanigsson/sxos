with Int_Flash;
with Store_Log;

--  Reading positions and settings, in the 32 KB of internal flash right
--  after the 1 MB app slot.
package Device_Store is new Store_Log
  (Int_Flash.App_End, Int_Flash.Read, Int_Flash.Program, Int_Flash.Erase);
