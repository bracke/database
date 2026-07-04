with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Queries;
with Database.Status;

--  View metadata and durable view query bodies.
package Database.Views is
   use Ada.Strings.Wide_Wide_Unbounded;
   --  View_Id defines a public database type used by this package.
   type View_Id is new Natural;
   --  View_Definition stores the public fields for this database abstraction.
   type View_Definition is record
      Id    : View_Id := 0;
      Name  : Unbounded_Wide_Wide_String;
      Query : Database.Queries.Query;
   end record;
   --  View_Vectors stores ordered view values for this package.
   package View_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => View_Definition);
   --  Return create for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Query query argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create (Name : Wide_Wide_String; Query : Database.Queries.Query) return View_Definition;
   --  Return validate for the supplied database state or arguments.
   --  @param View view argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate (View : View_Definition) return Database.Status.Result;
   --  Return expand for the supplied database state or arguments.
   --  @param View view argument supplied to the operation.
   --  @param Query query argument supplied to the operation.
   --  @return Result produced by the function.
   function Expand (View : View_Definition; Query : out Database.Queries.Query) return Database.Status.Result;
end Database.Views;
