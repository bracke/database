with Database.MVCC;
with Database.Versioning;

package Database.Visibility.Rules
  with SPARK_Mode => On
is
   use type Database.MVCC.Transaction_Lifecycle;

   function Created_Is_Visible
     (Tx_Id            : Database.Versioning.Transaction_Id;
      Snapshot         : Database.Versioning.Commit_Version;
      Created_By_Tx    : Database.Versioning.Transaction_Id;
      Created_Version  : Database.Versioning.Commit_Version;
      Created_Committed: Boolean;
      Created_Lifecycle: Database.MVCC.Transaction_Lifecycle) return Boolean
     with
       Global => null,
       Post =>
         (if Created_By_Tx = Tx_Id then Created_Is_Visible'Result
          elsif not Created_Committed then
            Created_Is_Visible'Result =
              (Created_Lifecycle = Database.MVCC.Committed
               and then Created_Version <= Snapshot)
          else Created_Is_Visible'Result = (Created_Version <= Snapshot));

   function Deleted_For
     (Tx_Id             : Database.Versioning.Transaction_Id;
      Snapshot          : Database.Versioning.Commit_Version;
      Deleted           : Boolean;
      Deleted_By_Tx     : Database.Versioning.Transaction_Id;
      Deleted_Version   : Database.Versioning.Commit_Version;
      Deleted_Lifecycle : Database.MVCC.Transaction_Lifecycle) return Boolean
     with
       Global => null,
       Post =>
         (if not Deleted then not Deleted_For'Result
          elsif Deleted_By_Tx = Tx_Id then Deleted_For'Result
          elsif Deleted_By_Tx /= Database.Versioning.No_Transaction then
            Deleted_For'Result =
              (Deleted_Lifecycle = Database.MVCC.Committed
               and then Deleted_Version /= Database.Versioning.No_Version
               and then Deleted_Version <= Snapshot)
          else Deleted_For'Result =
            (Deleted_Version /= Database.Versioning.No_Version
             and then Deleted_Version <= Snapshot));

   function Version_Is_Visible
     (Created_Visible : Boolean;
      Deleted         : Boolean) return Boolean
     with
       Global => null,
       Post => Version_Is_Visible'Result = (Created_Visible and then not Deleted);

   function Is_Own_Write
     (Tx_Id         : Database.Versioning.Transaction_Id;
      Created_By_Tx : Database.Versioning.Transaction_Id;
      Deleted_By_Tx : Database.Versioning.Transaction_Id) return Boolean
     with
       Global => null,
       Post => Is_Own_Write'Result =
         (Created_By_Tx = Tx_Id or else Deleted_By_Tx = Tx_Id);
end Database.Visibility.Rules;
