--  Inverted full-text index storage and lookup operations.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Full_Text.Normalization;
with Database.Full_Text.Postings;
with Database.Full_Text.Tokenizers;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Transactions;
with Database.Versioning;

--  Public specification for this database subsystem.
package Database.Full_Text.Indexes is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Full_Text_Index_Id defines a public database type used by this package.
   type Full_Text_Index_Id is new Natural;

   --  Full_Text_Index_Metadata stores the public fields for this database abstraction.
   type Full_Text_Index_Metadata is record
      Id          : Full_Text_Index_Id := 0;
      Name        : Unbounded_Wide_Wide_String;
      Table_Id    : Natural := 0;
      Table_Name  : Unbounded_Wide_Wide_String;
      Column_Id   : Natural := 0;
      Tokenizer    : Database.Full_Text.Tokenizers.Tokenizer_Config;
      Normalizer   : Database.Full_Text.Normalization.Normalization_Config;
      Root_Page    : Natural := 0;
      Posting_Root : Natural := 0;
      Owner_Key    : Natural := 0;
      Created_By   : Database.Versioning.Transaction_Id := Database.Versioning.No_Transaction;
      Created_At   : Database.Versioning.Commit_Version := Database.Versioning.No_Version;
      Deleted_By   : Database.Versioning.Transaction_Id := Database.Versioning.No_Transaction;
      Deleted_At   : Database.Versioning.Commit_Version := Database.Versioning.No_Version;
   end record;

   --  Metadata_Vectors stores ordered metadata values for this package.
   package Metadata_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Full_Text_Index_Metadata);

   --  Term_Entry stores the public fields for this database abstraction.
   type Term_Entry is record
      Term     : Unbounded_Wide_Wide_String;
      Postings : Database.Full_Text.Postings.Posting_Vectors.Vector;
   end record;

   --  Term_Entry_Vectors stores ordered term entry values for this package.
   package Term_Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Term_Entry);

   --  Document_Stat stores the public fields for this database abstraction.
   type Document_Stat is record
      Row_Id       : Natural := 0;
      Row_Key      : Unbounded_Wide_Wide_String;
      Token_Count  : Natural := 0;
      Deleted      : Boolean := False;
   end record;

   --  Document_Stat_Vectors stores ordered document stat values for this package.
   package Document_Stat_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Document_Stat);

   --  Full_Text_Index stores the public fields for this database abstraction.
   type Full_Text_Index is record
      Metadata : Full_Text_Index_Metadata;
      Terms    : Term_Entry_Vectors.Vector;
      Documents : Document_Stat_Vectors.Vector;
      Deleted_Posting_Count : Natural := 0;
   end record;

   --  Index_Vectors stores ordered index values for this package.
   package Index_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Full_Text_Index);

   --  Return validate definition for the supplied database state or arguments.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Column column argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Definition
     (Schema : Database.Schema.Table_Schema;
      Column : Natural) return Database.Status.Result;

   --  Return create for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Column column argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create
     (Name   : Wide_Wide_String;
      Schema : Database.Schema.Table_Schema;
      Column : Natural) return Full_Text_Index;

   --  Perform index row for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Tx transaction object that scopes the operation.
   --  @param Row_Id row id argument supplied to the operation.
   --  @param Row_Key row key argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   procedure Index_Row
     (Index   : in out Full_Text_Index;
      Tx      : in out Database.Transactions.Transaction;
      Row_Id  : Natural;
      Row_Key : Wide_Wide_String;
      Row     : Database.Rows.Row);

   --  Rebuild-time indexing for rows read from persistent storage.
   --  These postings are treated as already committed base state and are not
   --  associated with an active transaction.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Row_Id row id argument supplied to the operation.
   --  @param Row_Key row key argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   procedure Index_Row_Committed
     (Index   : in out Full_Text_Index;
      Row_Id  : Natural;
      Row_Key : Wide_Wide_String;
      Row     : Database.Rows.Row);

   --  Perform delete row for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Tx transaction object that scopes the operation.
   --  @param Row_Id row id argument supplied to the operation.
   --  @param Row_Key row key argument supplied to the operation.
   procedure Delete_Row
     (Index   : in out Full_Text_Index;
      Tx      : in out Database.Transactions.Transaction;
      Row_Id  : Natural;
      Row_Key : Wide_Wide_String);

   --  Return lookup for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Term term argument supplied to the operation.
   --  @return Result produced by the function.
   function Lookup
     (Index : Full_Text_Index;
      Term  : Wide_Wide_String) return Database.Full_Text.Postings.Posting_Vectors.Vector;

   --  Return lookup prefix for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Prefix prefix argument supplied to the operation.
   --  @return Result produced by the function.
   function Lookup_Prefix
     (Index  : Full_Text_Index;
      Prefix : Wide_Wide_String) return Database.Full_Text.Postings.Posting_Vectors.Vector;

   --  Return lookup fuzzy for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Term term argument supplied to the operation.
   --  @param Max_Edit_Distance max edit distance argument supplied to the operation.
   --  @return Result produced by the function.
   function Lookup_Fuzzy
     (Index             : Full_Text_Index;
      Term              : Wide_Wide_String;
      Max_Edit_Distance : Natural) return Database.Full_Text.Postings.Posting_Vectors.Vector;

   --  Return term count for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Number of items represented by the queried object.
   function Term_Count (Index : Full_Text_Index) return Natural;
   --  Return posting count for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Number of items represented by the queried object.
   function Posting_Count (Index : Full_Text_Index) return Natural;

   --  Return document count for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Number of items represented by the queried object.
   function Document_Count (Index : Full_Text_Index) return Natural;
   --  Return document length for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Row_Key row key argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Document_Length
     (Index   : Full_Text_Index;
      Row_Key : Wide_Wide_String) return Natural;
   --  Return average document length for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Number of items represented by the queried object.
   function Average_Document_Length (Index : Full_Text_Index) return Natural;
   --  Return document frequency for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Term term argument supplied to the operation.
   --  @return Result produced by the function.
   function Document_Frequency
     (Index : Full_Text_Index;
      Term  : Wide_Wide_String) return Natural;

   --  Perform recompute document statistics from postings for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   procedure Recompute_Document_Statistics_From_Postings
     (Index : in out Full_Text_Index);
end Database.Full_Text.Indexes;
