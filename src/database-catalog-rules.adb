package body Database.Catalog.Rules
  with SPARK_Mode => On
is
   function Next_Table_Id (Existing_Count : Natural) return Natural is
   begin
      return Existing_Count + 1;
   end Next_Table_Id;
end Database.Catalog.Rules;
