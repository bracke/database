with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
package body Database.Views is
   function Create (Name : Wide_Wide_String; Query : Database.Queries.Query) return View_Definition is
   begin
      return (Id => 0, Name => To_Unbounded_Wide_Wide_String (Name), Query => Query);
   end Create;
   function Validate (View : View_Definition) return Database.Status.Result is
   begin
      if Length (View.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "view name must not be empty");
      end if;
      return Database.Status.Success;
   end Validate;
   function Expand (View : View_Definition; Query : out Database.Queries.Query) return Database.Status.Result is
   begin
      Query := View.Query;
      return Validate (View);
   end Expand;
end Database.Views;
