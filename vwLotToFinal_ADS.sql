alter view vwLotToFinal_ADS
as
with FinalLots as (
    select
        Lot,
        RemainingQtty,
        ProducedQtty          -- ← adaugam si productia totala
    from LotBalance_ADS with (nolock)
    where RemainingQtty > 0
),

-- 1) Legaturi reale lot → final (din LotUsage_ADS)
RealLinks as (
    select
        SourceLot         = lu.InitialLot,
        FinalLot          = lu.FinalLot,
        ConsumedQty       = lu.InitialConsumedQty,
        ObtainedQty       = lu.FinalObtainedQty,
        Depth             = lu.Depth,
        Proportion        = lu.ProportionPer1Final,
        PctOfFinalLot     = lu.PctOfFinalLot,
        TotalProducedQtty = fl.ProducedQtty   -- ← nou: productia totala a lotului final
    from LotUsage_ADS lu with (nolock)
    join FinalLots fl
        on fl.Lot = lu.FinalLot
    where lu.Depth > 0                      -- doar consum real
),

-- 2) Loturi finale care nu apar în nicio relatie ca sursa
SelfFinalLots as (
    select
        SourceLot         = fl.Lot,
        FinalLot          = fl.Lot,
        ConsumedQty       = 0.0,
        ObtainedQty       = fl.RemainingQtty,
        Depth             = 0,
        Proportion        = 1.0,
        PctOfFinalLot     = 1.0,
        TotalProducedQtty = fl.ProducedQtty   -- ← la fel, din LotBalance_ADS
    from FinalLots fl
    where not exists (
        select 1
        from LotUsage_ADS lu
        where lu.InitialLot = fl.Lot
          and lu.Depth > 0
    )
)

-- UNION: rezultatul final (enumeram explicit coloanele)
select
    SourceLot,
    FinalLot,
    ConsumedQty,
    ObtainedQty,
    Depth,
    Proportion,
    PctOfFinalLot,
    TotalProducedQtty
from RealLinks

union all

select
    SourceLot,
    FinalLot,
    ConsumedQty,
    ObtainedQty,
    Depth,
    Proportion,
    PctOfFinalLot,
    TotalProducedQtty
from SelfFinalLots;