with Interfaces; use Interfaces;

--  The screen as the reader draws it: 480 x 800 portrait, 1 bit per pixel.
--
--  Callers use PORTRAIT coordinates (X right, Y down, origin top-left as the
--  device is held).  The bytes are kept in the UC8279's own RAM layout --
--  800 x 480 landscape, 100 bytes per row, MSB first, 1 = white -- so
--  X4_Display ships a Frame to the panel without converting it.  The rotation
--  confirmed on the X4 Pro is
--
--     portrait (X, Y)  ->  panel column Y, panel row 479 - X
--
--  Every drawing primitive clips: pixels outside the portrait area are
--  silently dropped, so callers may draw partly off-screen.
package Mono_Frame
  with SPARK_Mode => On
is
   Width  : constant := 480;   --  portrait
   Height : constant := 800;

   Panel_Width   : constant := Height;   --  landscape panel RAM
   Panel_Height  : constant := Width;
   Bytes_Per_Row : constant := Panel_Width / 8;
   Frame_Size    : constant := Bytes_Per_Row * Panel_Height;

   type Byte_Array is array (Natural range <>) of Unsigned_8;
   subtype Frame is Byte_Array (0 .. Frame_Size - 1);

   --  All white.
   procedure Clear (F : out Frame);

   procedure Plot (F : in out Frame; X, Y : Integer; Black : Boolean);

   function Is_Black (F : Frame; X, Y : Integer) return Boolean;
   --  False outside the portrait area.

   --  Solid rectangle, clipped.  Empty when W or H is not positive.
   procedure Fill_Rect
     (F : in out Frame; X, Y, W, H : Integer; Black : Boolean := True);

   --  One-pixel-wide outline of the same rectangle.
   procedure Frame_Rect
     (F : in out Frame; X, Y, W, H : Integer; Black : Boolean := True);

end Mono_Frame;
