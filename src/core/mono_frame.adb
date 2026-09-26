package body Mono_Frame
  with SPARK_Mode => On
is

   subtype Col_Index is Natural range 0 .. Width - 1;
   subtype Row_Index is Natural range 0 .. Height - 1;

   --  Byte index and bit mask of portrait pixel (X, Y).
   function Index (X : Col_Index; Y : Row_Index) return Natural is
     ((Panel_Height - 1 - X) * Bytes_Per_Row + Y / 8);

   function Mask (Y : Row_Index) return Unsigned_8 is
     (Shift_Left (Unsigned_8'(1), 7 - Y mod 8));

   procedure Clear (F : out Frame) is
   begin
      F := (others => 16#FF#);
   end Clear;

   procedure Clear (M : out Grey_Masks) is
   begin
      Clear (M.Grey);
      Clear (M.Dark);
   end Clear;

   procedure Plot (F : in out Frame; X, Y : Integer; Black : Boolean) is
   begin
      if X in Col_Index and then Y in Row_Index then
         if Black then
            F (Index (X, Y)) := F (Index (X, Y)) and not Mask (Y);
         else
            F (Index (X, Y)) := F (Index (X, Y)) or Mask (Y);
         end if;
      end if;
   end Plot;

   function Is_Black (F : Frame; X, Y : Integer) return Boolean is
     (X in Col_Index and then Y in Row_Index
      and then (F (Index (X, Y)) and Mask (Y)) = 0);

   procedure Fill_Rect
     (F : in out Frame; X, Y, W, H : Integer; Black : Boolean := True)
   is
      X0 : constant Integer := Integer'Max (X, 0);
      Y0 : constant Integer := Integer'Max (Y, 0);
      X1 : constant Integer :=
        (if W <= 0 or else X >= Width then -1
         elsif X >= 0 and then W - 1 > Width - 1 - X then Width - 1
         else Integer'Min (X + W - 1, Width - 1));
      Y1 : constant Integer :=
        (if H <= 0 or else Y >= Height then -1
         elsif Y >= 0 and then H - 1 > Height - 1 - Y then Height - 1
         else Integer'Min (Y + H - 1, Height - 1));
   begin
      for PX in X0 .. X1 loop
         for PY in Y0 .. Y1 loop
            Plot (F, PX, PY, Black);
         end loop;
      end loop;
   end Fill_Rect;

   procedure Frame_Rect
     (F : in out Frame; X, Y, W, H : Integer; Black : Boolean := True) is
   begin
      if W > 0 and then H > 0 then
         Fill_Rect (F, X, Y, W, 1, Black);
         --  The far edges are skipped when they lie beyond the frame, which
         --  also keeps Y + H - 1 and X + W - 1 in range.
         if Y < Height - H + 1 then
            Fill_Rect (F, X, Y + H - 1, W, 1, Black);
         end if;
         Fill_Rect (F, X, Y, 1, H, Black);
         if X < Width - W + 1 then
            Fill_Rect (F, X + W - 1, Y, 1, H, Black);
         end if;
      end if;
   end Frame_Rect;

end Mono_Frame;
