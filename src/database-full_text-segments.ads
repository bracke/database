--  Segment helpers for full-text inverted indexes.
--
--  The current storage engine can keep a full-text index as a mutable posting
--  dictionary, but large indexes benefit from a segment abstraction: new
--  postings are appended to small immutable-ish segments and maintenance can
--  merge them deterministically into larger compacted segments.  This package
--  is deliberately independent from the public search API so it can be used by
--  vacuum/check tools and by future background merge policies without exposing
--  SQL-like behavior.

with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Full_Text.Postings;

--  Public specification for this database subsystem.
package Database.Full_Text.Segments is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Segment_Id defines a public database type used by this package.
   type Segment_Id is new Natural;

   --  Segment_State defines a public database type used by this package.
   type Segment_State is
     (Mutable_Segment,
      Sealed_Segment,
      Obsolete_Segment);

   --  Segment_Metadata stores the public fields for this database abstraction.
   type Segment_Metadata is record
      Id             : Segment_Id := 0;
      State          : Segment_State := Mutable_Segment;
      Term_Count     : Natural := 0;
      Posting_Count  : Natural := 0;
      Obsolete_Count : Natural := 0;
   end record;

   --  Segment_Compaction_Policy controls explicit full-text segment merging.
   --  Compaction runs when either too many non-obsolete segments are present or
   --  the obsolete posting ratio reaches the configured threshold.
   type Segment_Compaction_Policy is record
      Max_Active_Segments       : Positive := 4;
      Minimum_Obsolete_Postings : Natural := 1;
      Minimum_Obsolete_Percent  : Natural range 0 .. 100 := 25;
   end record;

   Default_Compaction_Policy : constant Segment_Compaction_Policy :=
     (Max_Active_Segments       => 4,
      Minimum_Obsolete_Postings => 1,
      Minimum_Obsolete_Percent  => 25);

   --  Segment_Term stores the public fields for this database abstraction.
   type Segment_Term is record
      Term     : Unbounded_Wide_Wide_String;
      Postings : Database.Full_Text.Postings.Posting_Vectors.Vector;
   end record;

   --  Segment_Term_Vectors stores ordered segment term values for this package.
   package Segment_Term_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Segment_Term);

   --  Segment stores the public fields for this database abstraction.
   type Segment is record
      Metadata : Segment_Metadata;
      Terms    : Segment_Term_Vectors.Vector;
   end record;

   --  Segment_Vectors stores ordered segment values for this package.
   package Segment_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Segment);

   --  Return create for the supplied database state or arguments.
   --  @param Id id argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create (Id : Segment_Id) return Segment;

   --  Perform add posting for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   --  @param Term term argument supplied to the operation.
   --  @param Posting posting argument supplied to the operation.
   procedure Add_Posting
     (S       : in out Segment;
      Term    : Wide_Wide_String;
      Posting : Database.Full_Text.Postings.Posting);

   --  Return lookup for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   --  @param Term term argument supplied to the operation.
   --  @return Result produced by the function.
   function Lookup
     (S    : Segment;
      Term : Wide_Wide_String)
      return Database.Full_Text.Postings.Posting_Vectors.Vector;

   --  Perform seal for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   procedure Seal (S : in out Segment);
   --  Perform mark obsolete for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   procedure Mark_Obsolete (S : in out Segment);

   --  Return merge for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param New_Id new id argument supplied to the operation.
   --  @return Result produced by the function.
   function Merge
     (Left, Right : Segment;
      New_Id      : Segment_Id) return Segment;

   --  Return compact for the supplied database state or arguments.
   --  @param Input input argument supplied to the operation.
   --  @param New_Id new id argument supplied to the operation.
   --  @return Result produced by the function.
   function Compact
     (Input  : Segment_Vectors.Vector;
      New_Id : Segment_Id) return Segment;

   --  Return True when the supplied segment set crosses the configured
   --  compaction threshold.
   function Needs_Compaction
     (Input  : Segment_Vectors.Vector;
      Policy : Segment_Compaction_Policy := Default_Compaction_Policy)
      return Boolean;

   --  Apply the compaction policy in place. When Compacted is True, active
   --  segments are replaced by one sealed compacted segment and Next_Id is
   --  advanced.
   procedure Compact_With_Policy
     (Input     : in out Segment_Vectors.Vector;
      Next_Id   : in out Segment_Id;
      Compacted : out Boolean;
      Policy    : Segment_Compaction_Policy := Default_Compaction_Policy);

   --  Return segment count for the supplied database state or arguments.
   --  @param Input input argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Segment_Count (Input : Segment_Vectors.Vector) return Natural;
   --  Return posting count for the supplied database state or arguments.
   --  @param Input input argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Posting_Count (Input : Segment_Vectors.Vector) return Natural;
   --  Return obsolete count for the supplied database state or arguments.
   --  @param Input input argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Obsolete_Count (Input : Segment_Vectors.Vector) return Natural;
end Database.Full_Text.Segments;
