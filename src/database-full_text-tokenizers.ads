--  Unicode-aware tokenization support for Ada-native full-text indexes.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Extension_Metadata;
with Database.Status;

--  Public specification for this database subsystem.
package Database.Full_Text.Tokenizers is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Tokenizer_Kind enumerates the supported values for this database abstraction.
   type Tokenizer_Kind is (Unicode_Whitespace, Custom_Tokenizer);
   --  Built-in stop-word profiles used when Drop_Builtin_Stop_Words is True.
   --  These lists are intentionally small and deterministic. Applications that
   --  need deeper language analysis should register a custom tokenizer.
   type Stop_Word_Profile is
     (English_Stop_Words,
      Danish_Stop_Words,
      German_Stop_Words,
      French_Stop_Words);

   --  Token stores the public fields for this database abstraction.
   type Token is record
      Text         : Unbounded_Wide_Wide_String;
      Position     : Natural := 0;
      Start_Offset : Natural := 0;
      End_Offset   : Natural := 0;
   end record;

   --  Token_Vectors stores ordered token values for this package.
   package Token_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Token);

   --  Tokenizer_Config stores the public fields for this database abstraction.
   type Tokenizer_Config is record
      Kind                   : Tokenizer_Kind := Unicode_Whitespace;
      Treat_Punctuation_As_Separator : Boolean := True;
      --  Optional built-in stop-word filtering. Disabled by default so
      --  Phrase/position behavior remains exact unless callers opt in.
      Drop_Builtin_Stop_Words : Boolean := False;
      Builtin_Stop_Words      : Stop_Word_Profile := English_Stop_Words;
      --  Optional minimum token length. A value of 1 preserves every token.
      Minimum_Token_Length    : Positive := 1;
      Custom_Name             : Unbounded_Wide_Wide_String;
   end record;

   --  Return is builtin stop word for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Builtin_Stop_Word (Text : Wide_Wide_String) return Boolean;
   --  Return whether Text is a built-in stop word for Profile.
   function Is_Builtin_Stop_Word
     (Text    : Wide_Wide_String;
      Profile : Stop_Word_Profile) return Boolean;

   --  Return default config for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Default_Config return Tokenizer_Config;
   --  Tokenizer_Function defines a public database type used by this package.
   type Tokenizer_Function is access function
     (Text : Wide_Wide_String) return Token_Vectors.Vector;

   --  Custom_Tokenizer_Metadata stores the public fields for this database abstraction.
   type Custom_Tokenizer_Metadata is record
      Name             : Unbounded_Wide_Wide_String;
      Extension_Name   : Unbounded_Wide_Wide_String;
      Version          : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
      Deterministic    : Boolean := True;
   end record;

   --  Return register tokenizer for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Fn fn argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Register_Tokenizer
     (DB       : in out Database.Handle;
      Metadata : Custom_Tokenizer_Metadata;
      Fn       : Tokenizer_Function) return Database.Status.Result;

   --  Return tokenizer exists for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Tokenizer_Exists (Name : Wide_Wide_String) return Boolean;
   --  Return registered metadata for the supplied database state or arguments.
   --  @return Status result describing whether the operation succeeded.
   function Registered_Metadata return Database.Extension_Metadata.Metadata_Vectors.Vector;
   --  Selects the handle-owned callable registry used by legacy name-only lookup APIs.
   --  @param State_Key state key argument supplied to the operation.
   procedure Select_Database (State_Key : Natural);

   --  Drops all transient callable registrations owned by one database handle.
   --  @param State_Key state key argument supplied to the operation.
   procedure Drop_Database (State_Key : Natural);

   --  Perform clear custom tokenizers for the supplied database state or arguments.
   procedure Clear_Custom_Tokenizers;

   --  Return tokenize for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @param Config configuration values controlling the operation.
   --  @return Result produced by the function.
   function Tokenize
     (Text   : Wide_Wide_String;
      Config : Tokenizer_Config := Default_Config) return Token_Vectors.Vector;
end Database.Full_Text.Tokenizers;
