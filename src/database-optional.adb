package body Database.Optional is
   function None return Optional_Value is
   begin
      return (Present => False);
   end None;

   function With_Value (Value : Element_Type) return Optional_Value is
   begin
      return (Present => True, Item => Value);
   end With_Value;

   function Has_Value (Value : Optional_Value) return Boolean is
   begin
      return Value.Present;
   end Has_Value;

   function Get (Value : Optional_Value) return Element_Type is
   begin
      pragma Assert (Value.Present, "optional has no value");
      return Value.Item;
   end Get;
end Database.Optional;
