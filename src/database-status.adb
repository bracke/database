with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Status is
   use Ada.Strings.Wide_Wide_Unbounded;

   function Success return Result is
   begin
      return (Code => Ok, Message => Null_Unbounded_Wide_Wide_String);
   end Success;

   function Failure (Code : Status_Code; Message : Wide_Wide_String) return Result is
   begin
      return (Code => Code, Message => To_Unbounded_Wide_Wide_String (Message));
   end Failure;
end Database.Status;
