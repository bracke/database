--  Small generic optional value container used by public APIs.
generic
   --  Public type `Element_Type`.
   type Element_Type is private;
   --  Public nested package `Database.Optional`.
package Database.Optional is
   --  Public type `Optional_Value`.
   type Optional_Value is private;
   --  Public operation `None`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @return Result produced by the function.
   function None return Optional_Value;
   --  Public operation `With_Value`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Value typed value supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function With_Value (Value : Element_Type) return Optional_Value;
   --  Public operation `Has_Value`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Value typed value supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Has_Value (Value : Optional_Value) return Boolean;
   --  Public operation `Get`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Value typed value supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Get (Value : Optional_Value) return Element_Type;
private
   --  Public type `Optional_Value`.
   type Optional_Value (Present : Boolean := False) is record
      case Present is
         when True => Item : Element_Type;
         when False => null;
      end case;
   end record;
end Database.Optional;
