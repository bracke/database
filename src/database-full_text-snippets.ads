--  Unicode-safe snippet generation for full-text search results.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Full_Text.Queries;

--  Public specification for this database subsystem.
package Database.Full_Text.Snippets is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Snippet_Config stores the public fields for this database abstraction.
   type Snippet_Config is record
      Context_Code_Points : Natural := 32;
      Marker_Start        : Unbounded_Wide_Wide_String := To_Unbounded_Wide_Wide_String ("[");
      Marker_End          : Unbounded_Wide_Wide_String := To_Unbounded_Wide_Wide_String ("]");
   end record;

   --  Return default config for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Default_Config return Snippet_Config;

   --  Return a snippet around the first exact term from Query found in Text.
   --  The function operates on Wide_Wide_String indexes, so it never splits an
   --  Ada Wide_Wide_Character. It also avoids splitting adjacent Unicode
   --  combining-mark sequences at snippet and marker boundaries.
   --  @param Text text argument supplied to the operation.
   --  @param Query query argument supplied to the operation.
   --  @param Config configuration values controlling the operation.
   --  @return Result produced by the function.
   function Generate
     (Text   : Wide_Wide_String;
      Query  : Database.Full_Text.Queries.Query;
      Config : Snippet_Config := Default_Config) return Wide_Wide_String;
end Database.Full_Text.Snippets;
