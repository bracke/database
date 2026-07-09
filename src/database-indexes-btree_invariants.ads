with Interfaces;
use type Interfaces.Unsigned_32;

package Database.Indexes.BTree_Invariants
  with SPARK_Mode => On
is
   --  Key_Type defines a public database type used by this package.
   subtype Key_Type is Interfaces.Integer_64;
   --  Page_Id_Type defines a public database type used by this package.
   subtype Page_Id_Type is Interfaces.Unsigned_32;

   --  No_Page is a public constant used by this package.
   No_Page : constant Page_Id_Type := 0;

   --  Max_Keys_Per_Node is a public constant used by this package.
   Max_Keys_Per_Node : constant Natural := 64;
   --  Max_Children_Per_Node is a public constant used by this package.
   Max_Children_Per_Node : constant Natural := Max_Keys_Per_Node + 1;
   --  Max_Nodes is a public constant used by this package.
   Max_Nodes : constant Natural := 4_096;

   --  Node_Kind defines a public database type used by this package.
   type Node_Kind is
     (Internal_Node,
      Leaf_Node);

   --  Key_Array defines a public database type used by this package.
   type Key_Array is array (Positive range <>) of Key_Type;
   --  Page_Array defines a public database type used by this package.
   type Page_Array is array (Positive range <>) of Page_Id_Type;

   --  Node_Descriptor stores the public fields for this database abstraction.
   type Node_Descriptor is record
      Page_Id      : Page_Id_Type := No_Page;
      Parent_Id    : Page_Id_Type := No_Page;
      Kind         : Node_Kind := Leaf_Node;
      Depth        : Natural := 0;
      Key_Count    : Natural range 0 .. Max_Keys_Per_Node := 0;
      Child_Count  : Natural range 0 .. Max_Children_Per_Node := 0;
      Keys         : Key_Array (1 .. Max_Keys_Per_Node) := (others => 0);
      Children     : Page_Array (1 .. Max_Children_Per_Node) := (others => No_Page);
      Next_Leaf    : Page_Id_Type := No_Page;
      Previous_Leaf: Page_Id_Type := No_Page;
   end record;

   --  Node_Array defines a public database type used by this package.
   type Node_Array is array (Positive range <>) of Node_Descriptor;

   --  Validation_Status defines a public database type used by this package.
   type Validation_Status is
     (Valid,
      Empty_Tree,
      Invalid_Root,
      Invalid_Page_Id,
      Duplicate_Page_Id,
      Invalid_Key_Count,
      Invalid_Child_Count,
      Keys_Not_Strictly_Sorted,
      Internal_Node_Child_Count_Mismatch,
      Leaf_Node_Has_Children,
      Missing_Child,
      Missing_Parent,
      Parent_Link_Mismatch,
      Child_Key_Range_Violation,
      Leaf_Depth_Mismatch,
      Leaf_Link_Mismatch,
      Unreachable_Node,
      Node_Count_Exceeded);

   --  Tree_Descriptor stores the public fields for this database abstraction.
   type Tree_Descriptor is record
      Root_Page_Id : Page_Id_Type := No_Page;
      Node_Count   : Natural range 0 .. Max_Nodes := 0;
      Nodes        : Node_Array (1 .. Max_Nodes);
   end record;

   --  Return is active node for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Active_Node
     (Tree  : Tree_Descriptor;
      Index : Positive) return Boolean is
     (Index <= Tree.Node_Count)
     with
       Global => null,
       Depends => (Is_Active_Node'Result => (Tree, Index));

   --  Return find node index for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @param Page_Id page id argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Find_Node_Index
     (Tree    : Tree_Descriptor;
      Page_Id : Page_Id_Type) return Natural
     with
       Global => null,
       Depends => (Find_Node_Index'Result => (Tree, Page_Id)),
       Post =>
         Find_Node_Index'Result = 0
         or else
           (Find_Node_Index'Result in 1 .. Tree.Node_Count
            and then Tree.Nodes (Find_Node_Index'Result).Page_Id = Page_Id);

   --  Return contains page for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @param Page_Id page id argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Contains_Page
     (Tree    : Tree_Descriptor;
      Page_Id : Page_Id_Type) return Boolean is
     (Find_Node_Index (Tree, Page_Id) /= 0)
     with
       Global => null,
       Depends => (Contains_Page'Result => (Tree, Page_Id));

   --  Return keys are strictly sorted for the supplied database state or arguments.
   --  @param Node node argument supplied to the operation.
   --  @return Result produced by the function.
   function Keys_Are_Strictly_Sorted
     (Node : Node_Descriptor) return Boolean
     with
       Global => null,
       Depends => (Keys_Are_Strictly_Sorted'Result => Node);

   --  Return node key min for the supplied database state or arguments.
   --  @param Node node argument supplied to the operation.
   --  @return Result produced by the function.
   function Node_Key_Min
     (Node : Node_Descriptor) return Key_Type
     with
       Global => null,
       Pre => Node.Key_Count > 0,
       Depends => (Node_Key_Min'Result => Node);

   --  Return node key max for the supplied database state or arguments.
   --  @param Node node argument supplied to the operation.
   --  @return Result produced by the function.
   function Node_Key_Max
     (Node : Node_Descriptor) return Key_Type
     with
       Global => null,
       Pre => Node.Key_Count > 0,
       Depends => (Node_Key_Max'Result => Node);

   --  Validate invariants that can be checked from a single node descriptor.
   --  @param Node node argument supplied to the operation.
   --  @param Is_Root is root argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Node_Local
     (Node : Node_Descriptor;
      Is_Root : Boolean) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Node_Local'Result => (Node, Is_Root));

   --  Return validate page id uniqueness for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Page_Id_Uniqueness
     (Tree : Tree_Descriptor) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Page_Id_Uniqueness'Result => Tree);

   --  Return validate parent child links for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Parent_Child_Links
     (Tree : Tree_Descriptor) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Parent_Child_Links'Result => Tree);

   --  Return validate child key ranges for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Child_Key_Ranges
     (Tree : Tree_Descriptor) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Child_Key_Ranges'Result => Tree);

   --  Return validate leaf depths for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Leaf_Depths
     (Tree : Tree_Descriptor) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Leaf_Depths'Result => Tree);

   --  Return validate leaf links for the supplied database state or arguments.
   --  @param Tree tree argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Leaf_Links
     (Tree : Tree_Descriptor) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Leaf_Links'Result => Tree);

   --  Validate that every active node is reachable from the root.
   --  @param Tree tree argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Reachability
     (Tree : Tree_Descriptor) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Reachability'Result => Tree);

   --  Validate all supported structural B+ tree invariants.
   --  @param Tree tree argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Tree
     (Tree : Tree_Descriptor) return Validation_Status
     with
       Global => null,
       Depends => (Validate_Tree'Result => Tree);

end Database.Indexes.BTree_Invariants;
