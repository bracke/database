with Interfaces;
package body Database.Indexes.BTree_Invariants
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Integer_64;

   function Find_Node_Index
     (Tree    : Tree_Descriptor;
      Page_Id : Page_Id_Type) return Natural
   is
   begin
      if Page_Id = No_Page then
         return 0;
      end if;

      for Index in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

         if Tree.Nodes (Index).Page_Id = Page_Id then
            return Index;
         end if;
      end loop;

      return 0;
   end Find_Node_Index;

   function Keys_Are_Strictly_Sorted
     (Node : Node_Descriptor) return Boolean
   is
   begin
      if Node.Key_Count <= 1 then
         return True;
      end if;

      for Index in 2 .. Node.Key_Count loop
         pragma Loop_Invariant (Index in 2 .. Node.Key_Count);

         if Node.Keys (Index - 1) >= Node.Keys (Index) then
            return False;
         end if;
      end loop;

      return True;
   end Keys_Are_Strictly_Sorted;

   function Node_Key_Min
     (Node : Node_Descriptor) return Key_Type
   is
   begin
      return Node.Keys (1);
   end Node_Key_Min;

   function Node_Key_Max
     (Node : Node_Descriptor) return Key_Type
   is
   begin
      return Node.Keys (Node.Key_Count);
   end Node_Key_Max;

   function Validate_Node_Local
     (Node : Node_Descriptor;
      Is_Root : Boolean) return Validation_Status
   is
   begin
      if Node.Page_Id = No_Page then
         return Invalid_Page_Id;
      end if;

      if Node.Key_Count > Max_Keys_Per_Node then
         return Invalid_Key_Count;
      end if;

      if not Keys_Are_Strictly_Sorted (Node) then
         return Keys_Not_Strictly_Sorted;
      end if;

      case Node.Kind is
         when Leaf_Node =>
            if Node.Child_Count /= 0 then
               return Leaf_Node_Has_Children;
            end if;

         when Internal_Node =>
            if Node.Key_Count = 0 and then not Is_Root then
               return Invalid_Key_Count;
            end if;

            if Node.Child_Count /= Node.Key_Count + 1 then
               return Internal_Node_Child_Count_Mismatch;
            end if;

            for Child_Index in 1 .. Node.Child_Count loop
               pragma Loop_Invariant (Child_Index in 1 .. Node.Child_Count);

               if Node.Children (Child_Index) = No_Page then
                  return Missing_Child;
               end if;
            end loop;
      end case;

      return Valid;
   end Validate_Node_Local;

   function Validate_Page_Id_Uniqueness
     (Tree : Tree_Descriptor) return Validation_Status
   is
   begin
      if Tree.Node_Count = 0 then
         return Empty_Tree;
      end if;

      if Tree.Node_Count > Max_Nodes then
         return Node_Count_Exceeded;
      end if;

      for Left in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Left in 1 .. Tree.Node_Count);

         if Tree.Nodes (Left).Page_Id = No_Page then
            return Invalid_Page_Id;
         end if;

         for Right in Left + 1 .. Tree.Node_Count loop
            pragma Loop_Invariant (Right in Left + 1 .. Tree.Node_Count);

            if Tree.Nodes (Left).Page_Id = Tree.Nodes (Right).Page_Id then
               return Duplicate_Page_Id;
            end if;
         end loop;
      end loop;

      return Valid;
   end Validate_Page_Id_Uniqueness;

   function Validate_Parent_Child_Links
     (Tree : Tree_Descriptor) return Validation_Status
   is
      Root_Index  : Natural;
      Child_Index : Natural;
      Child_Page  : Page_Id_Type;
   begin
      Root_Index := Find_Node_Index (Tree, Tree.Root_Page_Id);
      if Root_Index = 0 then
         return Invalid_Root;
      end if;

      if Tree.Nodes (Root_Index).Parent_Id /= No_Page then
         return Parent_Link_Mismatch;
      end if;

      for Index in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

         declare
            Node : constant Node_Descriptor := Tree.Nodes (Index);
         begin
            if Index /= Root_Index and then Node.Parent_Id = No_Page then
               return Missing_Parent;
            end if;

            if Index /= Root_Index
              and then Find_Node_Index (Tree, Node.Parent_Id) = 0
            then
               return Missing_Parent;
            end if;

            if Node.Kind = Internal_Node then
               for Slot in 1 .. Node.Child_Count loop
                  pragma Loop_Invariant (Slot in 1 .. Node.Child_Count);

                  Child_Page := Node.Children (Slot);
                  Child_Index := Find_Node_Index (Tree, Child_Page);

                  if Child_Index = 0 then
                     return Missing_Child;
                  end if;

                  if Find_Node_Index (Tree, Tree.Nodes (Child_Index).Parent_Id) = 0 then
                     return Missing_Parent;
                  end if;

                  if Tree.Nodes (Child_Index).Parent_Id /= Node.Page_Id then
                     return Parent_Link_Mismatch;
                  end if;
               end loop;
            end if;
         end;
      end loop;

      return Valid;
   end Validate_Parent_Child_Links;

   function Validate_Child_Key_Ranges
     (Tree : Tree_Descriptor) return Validation_Status
   is
      Child_Index : Natural;
   begin
      for Index in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

         declare
            Node : constant Node_Descriptor := Tree.Nodes (Index);
         begin
            if Node.Kind = Internal_Node then
               if Node.Key_Count = 0 then
                  return Invalid_Key_Count;
               end if;

               for Slot in 1 .. Node.Child_Count loop
                  pragma Loop_Invariant (Slot in 1 .. Node.Child_Count);

                  Child_Index := Find_Node_Index (Tree, Node.Children (Slot));
                  if Child_Index = 0 then
                     return Missing_Child;
                  end if;

                  declare
                     Child : constant Node_Descriptor := Tree.Nodes (Child_Index);
                  begin
                     if Child.Key_Count > 0 then
                        if Slot = 1 then
                           if Child.Keys (Child.Key_Count) >= Node.Keys (1) then
                              return Child_Key_Range_Violation;
                           end if;
                        elsif Slot = Node.Child_Count then
                           if Child.Keys (1) <= Node.Keys (Node.Key_Count) then
                              return Child_Key_Range_Violation;
                           end if;
                        else
                           if Child.Keys (1) <= Node.Keys (Slot - 1)
                             or else Child.Keys (Child.Key_Count) >= Node.Keys (Slot)
                           then
                              return Child_Key_Range_Violation;
                           end if;
                        end if;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      return Valid;
   end Validate_Child_Key_Ranges;

   function Validate_Leaf_Depths
     (Tree : Tree_Descriptor) return Validation_Status
   is
      Expected_Depth : Natural := 0;
      Seen_Leaf      : Boolean := False;
   begin
      for Index in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

         if Tree.Nodes (Index).Kind = Leaf_Node then
            if not Seen_Leaf then
               Expected_Depth := Tree.Nodes (Index).Depth;
               Seen_Leaf := True;
            elsif Tree.Nodes (Index).Depth /= Expected_Depth then
               return Leaf_Depth_Mismatch;
            end if;
         end if;
      end loop;

      return Valid;
   end Validate_Leaf_Depths;

   function Validate_Leaf_Links
     (Tree : Tree_Descriptor) return Validation_Status
   is
      Next_Index : Natural;
      Prev_Index : Natural;
   begin
      for Index in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

         declare
            Node : constant Node_Descriptor := Tree.Nodes (Index);
         begin
            if Node.Kind = Leaf_Node then
               if Node.Next_Leaf /= No_Page then
                  Next_Index := Find_Node_Index (Tree, Node.Next_Leaf);
                  if Next_Index = 0 then
                     return Leaf_Link_Mismatch;
                  end if;

                  if Tree.Nodes (Next_Index).Kind /= Leaf_Node then
                     return Leaf_Link_Mismatch;
                  end if;

                  if Tree.Nodes (Next_Index).Previous_Leaf /= Node.Page_Id then
                     return Leaf_Link_Mismatch;
                  end if;

                  if Node.Key_Count > 0
                    and then Tree.Nodes (Next_Index).Key_Count > 0
                    and then Node.Keys (Node.Key_Count) >=
                      Tree.Nodes (Next_Index).Keys (1)
                  then
                     return Leaf_Link_Mismatch;
                  end if;
               end if;

               if Node.Previous_Leaf /= No_Page then
                  Prev_Index := Find_Node_Index (Tree, Node.Previous_Leaf);
                  if Prev_Index = 0 then
                     return Leaf_Link_Mismatch;
                  end if;

                  if Tree.Nodes (Prev_Index).Kind /= Leaf_Node then
                     return Leaf_Link_Mismatch;
                  end if;

                  if Tree.Nodes (Prev_Index).Next_Leaf /= Node.Page_Id then
                     return Leaf_Link_Mismatch;
                  end if;
               end if;
            end if;
         end;
      end loop;

      return Valid;
   end Validate_Leaf_Links;

   function Validate_Reachability
     (Tree : Tree_Descriptor) return Validation_Status
   is
      Reachable : array (1 .. Max_Nodes) of Boolean := (others => False);
      Changed   : Boolean := True;
      Root_Index : Natural;
      Child_Index : Natural;
      Remaining : Natural := Max_Nodes;
   begin
      Root_Index := Find_Node_Index (Tree, Tree.Root_Page_Id);
      if Root_Index = 0 then
         return Invalid_Root;
      end if;

      Reachable (Root_Index) := True;

      while Changed and then Remaining > 0 loop
         pragma Loop_Invariant (Root_Index in 1 .. Max_Nodes);
         pragma Loop_Variant (Decreases => Remaining);

         Changed := False;
         Remaining := Remaining - 1;

         for Index in 1 .. Tree.Node_Count loop
            pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

            if Reachable (Index)
              and then Tree.Nodes (Index).Kind = Internal_Node
            then
               for Slot in 1 .. Tree.Nodes (Index).Child_Count loop
                  pragma Loop_Invariant (Slot in 1 .. Tree.Nodes (Index).Child_Count);

                  Child_Index := Find_Node_Index
                    (Tree, Tree.Nodes (Index).Children (Slot));

                  if Child_Index = 0 then
                     return Missing_Child;
                  end if;

                  if not Reachable (Child_Index) then
                     Reachable (Child_Index) := True;
                     Changed := True;
                  end if;
               end loop;
            end if;
         end loop;
      end loop;

      if Changed then
         return Unreachable_Node;
      end if;

      for Index in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

         if not Reachable (Index) then
            return Unreachable_Node;
         end if;
      end loop;

      return Valid;
   end Validate_Reachability;

   function Validate_Tree
     (Tree : Tree_Descriptor) return Validation_Status
   is
      Status : Validation_Status;
      Root_Index : Natural;
   begin
      Status := Validate_Page_Id_Uniqueness (Tree);
      if Status /= Valid then
         return Status;
      end if;

      Root_Index := Find_Node_Index (Tree, Tree.Root_Page_Id);
      if Root_Index = 0 then
         return Invalid_Root;
      end if;

      for Index in 1 .. Tree.Node_Count loop
         pragma Loop_Invariant (Index in 1 .. Tree.Node_Count);

         Status := Validate_Node_Local
           (Tree.Nodes (Index),
            Is_Root => Index = Root_Index);
         if Status /= Valid then
            return Status;
         end if;
      end loop;

      Status := Validate_Parent_Child_Links (Tree);
      if Status /= Valid then
         return Status;
      end if;

      Status := Validate_Child_Key_Ranges (Tree);
      if Status /= Valid then
         return Status;
      end if;

      Status := Validate_Leaf_Depths (Tree);
      if Status /= Valid then
         return Status;
      end if;

      Status := Validate_Leaf_Links (Tree);
      if Status /= Valid then
         return Status;
      end if;

      Status := Validate_Reachability (Tree);
      if Status /= Valid then
         return Status;
      end if;

      return Valid;
   end Validate_Tree;

end Database.Indexes.BTree_Invariants;
