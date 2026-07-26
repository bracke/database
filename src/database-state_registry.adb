package body Database.State_Registry is

   Max_Open_Databases : constant := 256;
   type Slot_Count is range 0 .. Max_Open_Databases;
   subtype Slot_Index is Slot_Count range 1 .. Max_Open_Databases;

   type Slot is record
      Key : Natural := 0;
      Ptr : State_Access := null;
   end record;
   type Slot_Array is array (Slot_Index) of Slot;

   protected Reg is
      function Lookup (Key : Natural) return State_Access;
      procedure Add
        (Key : Natural; Value : State_Access; Winner : out State_Access);
      procedure Del (Key : Natural; Freed : out State_Access);
   private
      Slots : Slot_Array;
      Count : Slot_Count := 0;
   end Reg;

   protected body Reg is

      function Lookup (Key : Natural) return State_Access is
      begin
         for I in 1 .. Count loop
            if Slots (I).Key = Key then
               return Slots (I).Ptr;
            end if;
         end loop;
         return null;
      end Lookup;

      procedure Add
        (Key : Natural; Value : State_Access; Winner : out State_Access) is
      begin
         for I in 1 .. Count loop
            if Slots (I).Key = Key then
               Winner := Slots (I).Ptr;   --  another task registered it first
               return;
            end if;
         end loop;
         if Count < Max_Open_Databases then
            Count := Count + 1;
            Slots (Count) := (Key => Key, Ptr => Value);
         end if;
         --  On overflow the state is used unregistered (soft cap; not reached
         --  in practice with 256 concurrently-open databases).
         Winner := Value;
      end Add;

      procedure Del (Key : Natural; Freed : out State_Access) is
      begin
         Freed := null;
         for I in 1 .. Count loop
            if Slots (I).Key = Key then
               Freed := Slots (I).Ptr;
               Slots (I) := Slots (Count);   --  swap-remove keeps it packed
               Slots (Count) := (Key => 0, Ptr => null);
               Count := Count - 1;
               return;
            end if;
         end loop;
      end Del;

   end Reg;

   function Find (Key : Natural) return State_Access is (Reg.Lookup (Key));

   procedure Insert
     (Key    : Natural;
      Value  : State_Access;
      Winner : out State_Access) is
   begin
      Reg.Add (Key, Value, Winner);
   end Insert;

   procedure Remove (Key : Natural; Freed : out State_Access) is
   begin
      Reg.Del (Key, Freed);
   end Remove;

end Database.State_Registry;
