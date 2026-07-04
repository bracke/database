package body Database.Rows is
   use type Value_Vectors.Vector;

   overriding function "=" (Left, Right : Row) return Boolean is
   begin
      return Left.Values = Right.Values;
   end "=";
   procedure Append (R : in out Row; V : Database.Values.Value) is
   begin
      R.Values.Append (V);
   end Append;

   function Column_Count (R : Row) return Natural is
   begin
      return Natural (R.Values.Length);
   end Column_Count;

   function Get (R : Row; Index : Natural) return Database.Values.Value is
   begin
      return R.Values.Element (Index);
   end Get;

   procedure Replace (R : in out Row; Index : Natural; V : Database.Values.Value) is
   begin
      R.Values.Replace_Element (Index, V);
   end Replace;
end Database.Rows;
