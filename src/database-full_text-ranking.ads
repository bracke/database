--  Deterministic full-text ranking helpers.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Extension_Metadata;
with Database.Status;
with Database.Full_Text.Postings;

--  Public specification for this database subsystem.
package Database.Full_Text.Ranking is
   use Ada.Strings.Wide_Wide_Unbounded;
   --  Score defines a public database type used by this package.
   type Score is digits 15;

   --  Return frequency score for the supplied database state or arguments.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Frequency_Score (P : Database.Full_Text.Postings.Posting) return Score;

   --  Return matched term score for the supplied database state or arguments.
   --  @param Matched_Terms matched terms argument supplied to the operation.
   --  @param Frequency frequency argument supplied to the operation.
   --  @param Phrase_Bonus phrase bonus argument supplied to the operation.
   --  @return Result produced by the function.
   function Matched_Term_Score
     (Matched_Terms : Natural;
      Frequency     : Natural;
      Phrase_Bonus  : Boolean := False) return Score;

   --  BM25-style deterministic ranking. The formula intentionally avoids
   --  corpus-global hidden state: callers provide the document and term
   --  statistics observed by the index snapshot used for the search.
   --  @param Term_Frequency term frequency argument supplied to the operation.
   --  @param Document_Frequency document frequency argument supplied to the operation.
   --  @param Total_Documents total documents argument supplied to the operation.
   --  @param Document_Length document length argument supplied to the operation.
   --  @param Average_Document_Length average document length argument supplied to the operation.
   --  @return Result produced by the function.
   function BM25_Score
     (Term_Frequency          : Natural;
      Document_Frequency      : Natural;
      Total_Documents         : Natural;
      Document_Length         : Natural;
      Average_Document_Length : Score) return Score;

   --  Combined public scoring entry point used by Database.Full_Text.Search.
   --  It falls back to frequency ranking when statistics are insufficient.
   --  @param Posting posting argument supplied to the operation.
   --  @param Total_Documents total documents argument supplied to the operation.
   --  @param Document_Frequency document frequency argument supplied to the operation.
   --  @param Average_Document_Length average document length argument supplied to the operation.
   --  @param Document_Length document length argument supplied to the operation.
   --  @param Matched_Terms matched terms argument supplied to the operation.
   --  @param Phrase_Bonus phrase bonus argument supplied to the operation.
   --  @return Result produced by the function.
   function Query_Score
     (Posting                 : Database.Full_Text.Postings.Posting;
      Total_Documents         : Natural;
      Document_Frequency      : Natural;
      Average_Document_Length : Score;
      Document_Length         : Natural;
      Matched_Terms           : Natural := 1;
      Phrase_Bonus            : Boolean := False) return Score;

   --  Ranking_Context stores the public fields for this database abstraction.
   type Ranking_Context is record
      Term_Frequency : Natural := 0;
      Matched_Terms  : Natural := 0;
      Document_Length : Natural := 0;
   end record;

   --  Ranking_Function defines a public database type used by this package.
   type Ranking_Function is access function (Context : Ranking_Context) return Score;

   --  Ranking_Metadata stores the public fields for this database abstraction.
   type Ranking_Metadata is record
      Name             : Unbounded_Wide_Wide_String;
      Extension_Name   : Unbounded_Wide_Wide_String;
      Version          : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
      Deterministic    : Boolean := True;
   end record;

   --  Return register ranking function for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Fn fn argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Register_Ranking_Function
     (DB       : in out Database.Handle;
      Metadata : Ranking_Metadata;
      Fn       : Ranking_Function) return Database.Status.Result;

   --  Return score with for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Context context argument supplied to the operation.
   --  @param Score_Value score value argument supplied to the operation.
   --  @return Result produced by the function.
   function Score_With
     (Name    : Wide_Wide_String;
      Context : Ranking_Context;
      Score_Value : out Score) return Database.Status.Result;

   --  Return ranking function exists for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Ranking_Function_Exists (Name : Wide_Wide_String) return Boolean;
   --  Return registered metadata for the supplied database state or arguments.
   --  @return Status result describing whether the operation succeeded.
   function Registered_Metadata return Database.Extension_Metadata.Metadata_Vectors.Vector;
   --  Selects the handle-owned callable registry used by legacy name-only lookup APIs.
   --  @param State_Key state key argument supplied to the operation.
   procedure Select_Database (State_Key : Natural);

   --  Drops all transient callable registrations owned by one database handle.
   --  @param State_Key state key argument supplied to the operation.
   procedure Drop_Database (State_Key : Natural);

   --  Perform clear custom ranking for the supplied database state or arguments.
   procedure Clear_Custom_Ranking;
end Database.Full_Text.Ranking;
