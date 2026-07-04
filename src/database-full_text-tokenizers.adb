with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Extension_Metadata;
with Database.Status;
with Ada.Unchecked_Deallocation;

package body Database.Full_Text.Tokenizers is
   use type Ada.Containers.Count_Type;

   type Tokenizer_Entry is record
      Metadata : Custom_Tokenizer_Metadata;
      Fn       : Tokenizer_Function;
   end record;

   package Custom_Tokenizer_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Tokenizer_Entry);

   type Registry_Access is access all Custom_Tokenizer_Vectors.Vector;
   type Registry_State_Entry is record Key : Natural := 0;
   Registry : Registry_Access := null;
   end record;
   package Registry_State_Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Registry_State_Entry);
   procedure Free_Registry is new Ada.Unchecked_Deallocation  (Object => Custom_Tokenizer_Vectors.Vector,
     Name => Registry_Access);
   Default_Registry : aliased Custom_Tokenizer_Vectors.Vector;
   States : Registry_State_Vectors.Vector;
   Current_Key : Natural := 0;
   function Current_Registry return Registry_Access is
   begin
      if Current_Key = 0 then
         return Default_Registry'Access;
      end if;
      if States.Length > 0 then
         for I in 0 .. Natural (States.Length) - 1 loop
            if States.Element (I).Key = Current_Key then
               return States.Element (I).Registry;
            end if;
         end loop;
      end if;
      declare
         E : Registry_State_Entry;
      begin
         E.Key := Current_Key;
         E.Registry := new Custom_Tokenizer_Vectors.Vector;
         States.Append (E);
         return E.Registry;
      end;
   end Current_Registry;

   procedure Select_Database (State_Key : Natural) is
   begin
      Current_Key := State_Key;
      if State_Key /= 0 then
         declare
            Ignore : constant Registry_Access := Current_Registry;
            pragma Unreferenced (Ignore);
         begin
            null;
         end;
      end if;
   end Select_Database;

   procedure Drop_Database (State_Key : Natural) is
   begin
      if State_Key = 0 then
         return;
      end if;
      if States.Length > 0 then
         for I in reverse 0 .. Natural (States.Length)-1 loop
            if States.Element (I).Key = State_Key then
               declare
                  E : Registry_State_Entry := States.Element (I);
               begin
                  if E.Registry /= null then
                     Free_Registry (E.Registry);
                  end if;
                  States.Delete (I);
               end;
            end if;
         end loop;
      end if;
      if Current_Key = State_Key then
         Current_Key := 0;
      end if;
   end Drop_Database;

   function Find_Custom (Name : Wide_Wide_String) return Natural is
   begin
      if Current_Registry.all.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (Current_Registry.all.Length) - 1 loop
         if To_Wide_Wide_String (Current_Registry.all.Element (I).Metadata.Name) = Name then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Custom;

   function Register_Tokenizer
     (DB       : in out Database.Handle;
      Metadata : Custom_Tokenizer_Metadata;
      Fn       : Tokenizer_Function) return Database.Status.Result is
      Pos : Natural;
      E   : Tokenizer_Entry;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Pos := Find_Custom (To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Fn = null or else not Metadata.Deterministic then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid custom tokenizer registration");
      end if;
      E.Metadata := Metadata;
      E.Fn := Fn;
      if Pos = Natural'Last then
         Current_Registry.all.Append (E);
      else
         Current_Registry.all.Replace_Element (Pos, E);
      end if;
      return Database.Status.Success;
   end Register_Tokenizer;

   function Tokenizer_Exists (Name : Wide_Wide_String) return Boolean is
   begin
      return Find_Custom (Name) /= Natural'Last;
   end Tokenizer_Exists;

   function Registered_Metadata return Database.Extension_Metadata.Metadata_Vectors.Vector is
      V : Database.Extension_Metadata.Metadata_Vectors.Vector;
      M : Database.Extension_Metadata.Extension_Object_Metadata;
   begin
      if Current_Registry.all.Length = 0 then
         return V;
      end if;
      for I in 0 .. Natural (Current_Registry.all.Length) - 1 loop
         M.Extension_Name := Current_Registry.all.Element (I).Metadata.Extension_Name;
         M.Object_Name := Current_Registry.all.Element (I).Metadata.Name;
         M.Object_Kind := Database.Extension_Metadata.Tokenizer_Object;
         M.Version := Current_Registry.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Current_Registry.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism := Database.Extension_Metadata.Deterministic;
         V.Append (M);
      end loop;
      return V;
   end Registered_Metadata;

   procedure Clear_Custom_Tokenizers is
   begin
      Current_Registry.all.Clear;
   end Clear_Custom_Tokenizers;
   function Default_Config return Tokenizer_Config is
   begin
      return
        (Kind => Unicode_Whitespace,
         Treat_Punctuation_As_Separator => True,
         Drop_Builtin_Stop_Words => False,
         Minimum_Token_Length => 1,
         Custom_Name => Null_Unbounded_Wide_Wide_String);
   end Default_Config;

   function To_Basic_Lower (S : Wide_Wide_String) return Wide_Wide_String is
      R : Wide_Wide_String := S;
   begin
      for I in R'Range loop
         if R (I) >= 'A' and then R (I) <= 'Z' then
            R (I) := Wide_Wide_Character'Val
              (Wide_Wide_Character'Pos (R (I)) + 32);
         end if;
      end loop;
      return R;
   end To_Basic_Lower;

   function Is_Builtin_Stop_Word (Text : Wide_Wide_String) return Boolean is
      T : constant Wide_Wide_String := To_Basic_Lower (Text);
   begin
      --  Deliberately tiny and documented. This is not a language analyzer and
      --  should not be mistaken for locale-aware stop-word processing.
      return T = "a" or else T = "an" or else T = "and" or else T = "are"
        or else T = "as" or else T = "at" or else T = "be" or else T = "by"
        or else T = "for" or else T = "from" or else T = "in"
        or else T = "is" or else T = "it" or else T = "of"
        or else T = "on" or else T = "or" or else T = "the"
        or else T = "to" or else T = "with";
   end Is_Builtin_Stop_Word;

   function Is_Whitespace (C : Wide_Wide_Character) return Boolean is
   begin
      return C = ' ' or else C = Wide_Wide_Character'Val (9) or else C = Wide_Wide_Character'Val (10)
        or else C = Wide_Wide_Character'Val (13) or else C = Wide_Wide_Character'Val (16#00A0#);
   end Is_Whitespace;

   function Is_ASCII_Alnum (C : Wide_Wide_Character) return Boolean is
   begin
      return (C >= 'a' and then C <= 'z') or else (C >= 'A' and then C <= 'Z')
        or else (C >= '0' and then C <= '9') or else Wide_Wide_Character'Pos (C) > 127;
   end Is_ASCII_Alnum;

   function Is_Separator (C : Wide_Wide_Character; Config : Tokenizer_Config) return Boolean is
   begin
      if Is_Whitespace (C) then
         return True;
      end if;
      return Config.Treat_Punctuation_As_Separator and then not Is_ASCII_Alnum (C);
   end Is_Separator;

   procedure Append_Token
     (Result : in out Token_Vectors.Vector;
      Text   : Wide_Wide_String;
      First  : Natural;
      Last   : Natural;
      Base   : Natural;
      Pos    : Natural;
      Config : Tokenizer_Config) is
      Token_Text : constant Wide_Wide_String := Text (First .. Last);
   begin
      if Token_Text'Length < Config.Minimum_Token_Length then
         return;
      end if;
      if Config.Drop_Builtin_Stop_Words and then Is_Builtin_Stop_Word (Token_Text) then
         return;
      end if;
      Result.Append
        (Token'(Text => To_Unbounded_Wide_Wide_String (Token_Text),
          Position => Pos,
          Start_Offset => First - Base,
          End_Offset => Last - Base + 1));
   end Append_Token;

   function Tokenize
     (Text   : Wide_Wide_String;
      Config : Tokenizer_Config := Default_Config) return Token_Vectors.Vector is
      Result : Token_Vectors.Vector;
      First  : Natural := 0;
      Pos    : Natural := 0;
      In_Token : Boolean := False;
   begin
      if Config.Kind = Custom_Tokenizer then
         declare
            Pos_Custom : constant Natural := Find_Custom (To_Wide_Wide_String (Config.Custom_Name));
         begin
            if Pos_Custom = Natural'Last then
               return Result;
            end if;
            return Current_Registry.all.Element (Pos_Custom).Fn.all (Text);
         end;
      elsif Config.Kind /= Unicode_Whitespace then
         return Result;
      end if;
      for I in Text'Range loop
         if Is_Separator (Text (I), Config) then
            if In_Token then
               Append_Token (Result, Text, First, I - 1, Text'First, Pos, Config);
               Pos := Pos + 1;
               In_Token := False;
            end if;
         elsif not In_Token then
            First := I;
            In_Token := True;
         end if;
      end loop;
      if In_Token then
         Append_Token (Result, Text, First, Text'Last, Text'First, Pos, Config);
      end if;
      return Result;
   end Tokenize;
end Database.Full_Text.Tokenizers;
