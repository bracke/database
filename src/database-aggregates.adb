package body Database.Aggregates is
   function Count return Aggregate is (Kind => Count_All, Column => 0);
   function Count (Column : Natural) return Aggregate is (Kind => Count_Column, Column => Column);
   function Min (Column : Natural) return Aggregate is (Kind => Minimum, Column => Column);
   function Max (Column : Natural) return Aggregate is (Kind => Maximum, Column => Column);
   function Sum (Column : Natural) return Aggregate is (Kind => Total, Column => Column);
   function Avg (Column : Natural) return Aggregate is (Kind => Average, Column => Column);
end Database.Aggregates;
