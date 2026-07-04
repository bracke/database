--  Posting-list representation and merge helpers for full-text indexes.
with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Database.Versioning;
with Ada.Strings.Wide_Wide_Unbounded;

--  Public specification for this database subsystem.
package Database.Full_Text.Postings is
   --  Position_Vectors stores ordered position values for this package.
   package Position_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Natural);

   --  Row_Reference stores the public fields for this database abstraction.
   type Row_Reference is record
      Table_Id : Natural := 0;
      Row_Id   : Natural := 0;
      Row_Key  : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Column_Id : Natural := 0;
   end record;

   --  Posting stores the public fields for this database abstraction.
   type Posting is record
      Ref        : Row_Reference;
      Frequency  : Natural := 0;
      Positions  : Position_Vectors.Vector;
      Created_By : Database.Versioning.Transaction_Id := 0;
      Created_At : Database.Versioning.Commit_Version := 0;
      Deleted_By : Database.Versioning.Transaction_Id := 0;
      Deleted_At : Database.Versioning.Commit_Version := 0;
   end record;

   --  Posting_Vectors stores ordered posting values for this package.
   package Posting_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Posting);

   --  Skip_Entry stores the public fields for this database abstraction.
   type Skip_Entry is record
      From_Index : Natural := 0;
      To_Index   : Natural := 0;
      Target     : Row_Reference;
   end record;

   --  Skip_Entry_Vectors stores ordered skip entry values for this package.
   package Skip_Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Skip_Entry);

   --  Return build skip table for the supplied database state or arguments.
   --  @param Postings postings argument supplied to the operation.
   --  @param Stride stride argument supplied to the operation.
   --  @return Result produced by the function.
   function Build_Skip_Table
     (Postings : Posting_Vectors.Vector;
      Stride   : Positive := 8) return Skip_Entry_Vectors.Vector;

   --  Return intersect with skips for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Stride stride argument supplied to the operation.
   --  @return Result produced by the function.
   function Intersect_With_Skips
     (Left, Right : Posting_Vectors.Vector;
      Stride      : Positive := 8) return Posting_Vectors.Vector;

   --  Return same row for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Same_Row (Left, Right : Row_Reference) return Boolean;
   --  Perform add position for the supplied database state or arguments.
   --  @param P p argument supplied to the operation.
   --  @param Position position argument supplied to the operation.
   procedure Add_Position (P : in out Posting; Position : Natural);
   --  Return intersect for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Intersect (Left, Right : Posting_Vectors.Vector) return Posting_Vectors.Vector;
   --  Return union for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Union (Left, Right : Posting_Vectors.Vector) return Posting_Vectors.Vector;
   --  Return difference for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Difference (Left, Right : Posting_Vectors.Vector) return Posting_Vectors.Vector;
   --  Return phrase match for the supplied database state or arguments.
   --  @param P p argument supplied to the operation.
   --  @param Required_Positions required positions argument supplied to the operation.
   --  @return Result produced by the function.
   function Phrase_Match (P : Posting; Required_Positions : Position_Vectors.Vector) return Boolean;

   --  Return phrase intersect for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Offset offset argument supplied to the operation.
   --  @return Result produced by the function.
   function Phrase_Intersect
     (Left   : Posting_Vectors.Vector;
      Right  : Posting_Vectors.Vector;
      Offset : Positive) return Posting_Vectors.Vector;

   --  Return near intersect for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Max_Distance max distance argument supplied to the operation.
   --  @return Result produced by the function.
   function Near_Intersect
     (Left         : Posting_Vectors.Vector;
      Right        : Posting_Vectors.Vector;
      Max_Distance : Positive) return Posting_Vectors.Vector;
end Database.Full_Text.Postings;
