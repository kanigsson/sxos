with Card;
with Font_Catalog;
with Mono_Frame;
with Shelf;

--  The application's large state, kept off the 64 KB environment stack (an
--  overflow there is silent: the first version of the Library hung in its
--  first Clear with the frame and the shelf as locals of Main).
package App_State is

   --  In DRAM: the panel's SPI transfers read the frame directly.
   Screen : Mono_Frame.Frame;
   Volume : Card.FS.Volume;
   Faces  : Font_Catalog.List;

   --  ~35 KB, on the heap, which is in PSRAM.
   type Shelf_Access is access Shelf.List;
   Books : constant Shelf_Access := new Shelf.List;

end App_State;
