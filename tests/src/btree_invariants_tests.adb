with AUnit.Assertions;

with Database.Indexes.BTree_Invariants;

package body BTree_Invariants_Tests is
   use AUnit.Assertions;
   use type Database.Indexes.BTree_Invariants.Validation_Status;
   use type Database.Indexes.BTree_Invariants.Page_Id_Type;

   procedure Build_Valid_Tree
     (Tree : out Database.Indexes.BTree_Invariants.Tree_Descriptor) is
   begin
      Tree := (Root_Page_Id => 1, Node_Count => 3, Nodes => (others => <>));

      Tree.Nodes (1).Page_Id := 1;
      Tree.Nodes (1).Parent_Id := 0;
      Tree.Nodes (1).Kind := Database.Indexes.BTree_Invariants.Internal_Node;
      Tree.Nodes (1).Depth := 0;
      Tree.Nodes (1).Key_Count := 1;
      Tree.Nodes (1).Child_Count := 2;
      Tree.Nodes (1).Keys (1) := 50;
      Tree.Nodes (1).Children (1) := 2;
      Tree.Nodes (1).Children (2) := 3;

      Tree.Nodes (2).Page_Id := 2;
      Tree.Nodes (2).Parent_Id := 1;
      Tree.Nodes (2).Kind := Database.Indexes.BTree_Invariants.Leaf_Node;
      Tree.Nodes (2).Depth := 1;
      Tree.Nodes (2).Key_Count := 2;
      Tree.Nodes (2).Child_Count := 0;
      Tree.Nodes (2).Keys (1) := 10;
      Tree.Nodes (2).Keys (2) := 20;
      Tree.Nodes (2).Next_Leaf := 3;

      Tree.Nodes (3).Page_Id := 3;
      Tree.Nodes (3).Parent_Id := 1;
      Tree.Nodes (3).Kind := Database.Indexes.BTree_Invariants.Leaf_Node;
      Tree.Nodes (3).Depth := 1;
      Tree.Nodes (3).Key_Count := 2;
      Tree.Nodes (3).Child_Count := 0;
      Tree.Nodes (3).Keys (1) := 60;
      Tree.Nodes (3).Keys (2) := 70;
      Tree.Nodes (3).Previous_Leaf := 2;
   end Build_Valid_Tree;

   procedure Test_Valid_Tree (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Unsorted_Keys
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Duplicate_Page_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Bad_Parent_Link
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Child_Range_Violation
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Leaf_Depth_Mismatch
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Leaf_Link_Mismatch
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Unreachable_Node
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Leaf_With_Children
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("SPARK-friendly B+ tree invariants");
   end Name;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Valid_Tree'Access, "valid B+ tree descriptor passes");
      Register_Routine
        (T, Test_Rejects_Unsorted_Keys'Access, "unsorted keys rejected");
      Register_Routine
        (T,
         Test_Rejects_Duplicate_Page_Id'Access,
         "duplicate page ids rejected");
      Register_Routine
        (T, Test_Rejects_Bad_Parent_Link'Access, "bad parent link rejected");
      Register_Routine
        (T,
         Test_Rejects_Child_Range_Violation'Access,
         "child key range violation rejected");
      Register_Routine
        (T,
         Test_Rejects_Leaf_Depth_Mismatch'Access,
         "leaf depth mismatch rejected");
      Register_Routine
        (T,
         Test_Rejects_Leaf_Link_Mismatch'Access,
         "leaf link mismatch rejected");
      Register_Routine
        (T, Test_Rejects_Unreachable_Node'Access, "unreachable node rejected");
      Register_Routine
        (T,
         Test_Rejects_Leaf_With_Children'Access,
         "leaf child count rejected");
   end Register_Tests;

   procedure Test_Valid_Tree (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Valid,
         "valid tree should pass invariants");
   end Test_Valid_Tree;

   procedure Test_Rejects_Unsorted_Keys
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Nodes (2).Keys (1) := 30;
      Tree.Nodes (2).Keys (2) := 20;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Keys_Not_Strictly_Sorted,
         "unsorted keys must be rejected");
   end Test_Rejects_Unsorted_Keys;

   procedure Test_Rejects_Duplicate_Page_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Nodes (3).Page_Id := 2;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Duplicate_Page_Id,
         "duplicate page id must be rejected");
   end Test_Rejects_Duplicate_Page_Id;

   procedure Test_Rejects_Bad_Parent_Link
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Nodes (2).Parent_Id := 99;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Missing_Parent,
         "missing parent must be rejected");
   end Test_Rejects_Bad_Parent_Link;

   procedure Test_Rejects_Child_Range_Violation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Nodes (2).Keys (2) := 55;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Child_Key_Range_Violation,
         "child range violation must be rejected");
   end Test_Rejects_Child_Range_Violation;

   procedure Test_Rejects_Leaf_Depth_Mismatch
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Nodes (3).Depth := 2;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Leaf_Depth_Mismatch,
         "leaf depth mismatch must be rejected");
   end Test_Rejects_Leaf_Depth_Mismatch;

   procedure Test_Rejects_Leaf_Link_Mismatch
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Nodes (3).Previous_Leaf := 0;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Leaf_Link_Mismatch,
         "broken leaf back-link must be rejected");
   end Test_Rejects_Leaf_Link_Mismatch;

   procedure Test_Rejects_Unreachable_Node
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Node_Count := 4;
      Tree.Nodes (4).Page_Id := 4;
      Tree.Nodes (4).Parent_Id := 0;
      Tree.Nodes (4).Kind := Database.Indexes.BTree_Invariants.Leaf_Node;
      Tree.Nodes (4).Depth := 1;
      Tree.Nodes (4).Key_Count := 1;
      Tree.Nodes (4).Keys (1) := 100;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Missing_Parent,
         "unreachable non-root node without parent must be rejected");
   end Test_Rejects_Unreachable_Node;

   procedure Test_Rejects_Leaf_With_Children
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor;
   begin
      Build_Valid_Tree (Tree);
      Tree.Nodes (2).Child_Count := 1;
      Tree.Nodes (2).Children (1) := 99;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Leaf_Node_Has_Children,
         "leaf node with children must be rejected");
   end Test_Rejects_Leaf_With_Children;

end BTree_Invariants_Tests;
