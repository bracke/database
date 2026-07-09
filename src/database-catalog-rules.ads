package Database.Catalog.Rules
  with SPARK_Mode => On
is
   function Can_Allocate_Table_Id (Existing_Count : Natural) return Boolean is
     (Existing_Count < Natural'Last);

   function Next_Table_Id (Existing_Count : Natural) return Natural
     with
       Global => null,
       Pre => Can_Allocate_Table_Id (Existing_Count),
       Post =>
         Next_Table_Id'Result = Existing_Count + 1
         and then Next_Table_Id'Result > 0
         and then Next_Table_Id'Result > Existing_Count;

   function Is_Assigned_Table_Id (Table_Id : Natural) return Boolean is
     (Table_Id > 0);
end Database.Catalog.Rules;
