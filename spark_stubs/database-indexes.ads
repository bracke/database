package Database.Indexes
  with SPARK_Mode => On
is
   type Row_Reference is record
      Page        : Natural := 0;
      Slot_Offset : Natural := 0;
   end record;

   Invalid_Row_Reference : constant Row_Reference :=
     (Page => 0, Slot_Offset => 0);
end Database.Indexes;
