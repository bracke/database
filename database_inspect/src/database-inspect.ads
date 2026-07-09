with Database.Status;

package Database.Inspect is
   type Output_Procedure is access procedure (Line : Wide_Wide_String);

   function List_Schemas
     (DB  : in out Database.Handle;
      Put : not null Output_Procedure) return Database.Status.Result;

   function List_Indexes
     (DB  : in out Database.Handle;
      Put : not null Output_Procedure) return Database.Status.Result;

   function Dump_Table
     (DB         : in out Database.Handle;
      Table_Name : Wide_Wide_String;
      Put        : not null Output_Procedure;
      Limit      : Natural := Natural'Last) return Database.Status.Result;

   function Dump_All
     (DB    : in out Database.Handle;
      Put   : not null Output_Procedure;
      Limit : Natural := Natural'Last) return Database.Status.Result;
end Database.Inspect;
