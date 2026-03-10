alter procedure uspTrasabilitateLoturi_ADS
as
begin

	Prep:
	begin
		exec updLotNumber_ADS
		exec updEventLotNumber_ADS
	end

	DataSources:
	begin
		set nocount on 

		truncate table Manufacturing_ADS

		drop table if exists #Initial, #MnfgOutput, #MnfgInput, #Manufacturing

		create table #Initial
			(LotNumber uniqueidentifier, SourceLotNumber uniqueidentifier, Qtty money, SourceQtty money, Info varchar(255))

		create table #MnfgOutput
			(DocumentTypeId int, TransactionTypeId int, DocumentId int, EventId int, SiteId int, ItemId int,
			LotNumberWMS uniqueidentifier, KgQtty money, Info varchar(255))

		create table #MnfgInput
			(DocumentId int, SiteId int, ItemId int, 
			LotNumberWMS uniqueidentifier, Qtty money, KgQtty money)

		create table #Manufacturing
			(LotNumber uniqueidentifier, SourceLotNumber uniqueidentifier, Qtty float, SourceQtty float, Info varchar(255))

		insert into #Initial
			(LotNumber, SourceLotNumber, Qtty, SourceQtty, Info)
		select a.LotNumberWMS, a.LotNumberWMS, sum(a.Qtty / isnull(muc.ConvertionRate,1)), sum(a.Qtty / isnull(muc.ConvertionRate,1)),'NIR'
		from LotNumber_ADS a (nolock)
		join Item it (nolock) on a.ItemId=it.ItemId
		left join MeasuringUnitConvert muc on it.ItemId=muc.ItemId and it.MeasuringUnitId=muc.MeasuringUnitId and muc.BaseMeasuringUnitId=3
		where a.DocumentTypeId=3003
			and exists (
				select 1 from vwSE_Event e
				where a.EventId=e.EventId and a.SiteId=e.SiteId
					and e.BMoment>'20240930')
		group by a.LotNumberWMS

		insert into #MnfgOutput
			(DocumentTypeId, TransactionTypeId, DocumentId, EventId, SiteId, ItemId, 
			LotNumberWMS, KgQtty, Info)
		select a.DocumentTypeId, bt.TransactionTypeId, e.DocumentId, a.EventId, a.SiteId, a.ItemId, 
			a.LotNumberWMS, KgQtty=a.Qtty/isnull(muc.ConvertionRate,1), Info=tt.TransactionTypeName
		from TransactionType tt (nolock)
		join BusinessTransaction bt (nolock) on bt.TransactionTypeId=tt.TransactionTypeId
		join vwSE_Event e on e.DocumentId=bt.DestDocId and e.SiteId=bt.SiteId
		join LotNumber_ADS a (nolock) on a.EventId=e.EventId and a.SiteId=e.SiteId
		join Item it (nolock) on a.ItemId=it.ItemId
		left join MeasuringUnitConvert muc on it.ItemId=muc.ItemId and it.MeasuringUnitId=muc.MeasuringUnitId and muc.BaseMeasuringUnitId=3
		where a.DocumentTypeId=5004
			and e.BMoment>='20241201'
			and bt.TransactionTypeId in (
							749, /*Raport Compunere WMS*/
							752, /*Raport Transformare WMS*/
							753  /*Raport Descompunere WMS*/)

		create index Idx#MnfgOutput on #MnfgOutput (DocumentId, SiteId) include (KgQtty,Info)

		insert into #MnfgInput
			(DocumentId, SiteId, ItemId, LotNumberWMS, Qtty)
		select a.DocumentId, a.SiteId, e.ItemId, x.LotNumberWMS, Qtty=sum(x.Qtty)
		from (
			select a.DocumentId, a.SiteId, KgQtty=sum(a.KgQtty)
			from #MnfgOutput a
			group by a.DocumentId, a.SiteId
			) a
		join vwSE_Event e on a.DocumentId=e.DocumentId and a.SiteId=e.SiteId
		join EventLotNumber_ADS x (nolock) on e.EventId=x.EventId and e.SiteId=x.SiteId
		where exists (
			select 1 from mOutput op (nolock) 
			where e.EventId=op.EventId and e.SiteId=op.SiteId)
		group by a.DocumentId, a.SiteId, x.LotNumberWMS, e.ItemId

		update op
		set KgQtty=-(op.Qtty/isnull(muc.ConvertionRate,1))
		from #MnfgInput op
		join Item it (nolock) on op.ItemId=it.ItemId
		left join MeasuringUnitConvert muc on it.ItemId=muc.ItemId and it.MeasuringUnitId=muc.MeasuringUnitId and muc.BaseMeasuringUnitId=3

		insert into Manufacturing_ADS
			(DocumentId, SiteId, ItemId, LotNumberWMS, SourceLotNumberWMS, Info, SourceQtty, Qtty)
		select a.DocumentId, a.SiteId, a.ItemId, a.LotNumberWMS, c.LotNumberWMS, a.Info,
			SourceQtty=sum(c.KgQtty),
			Qtty=sum(a.KgQtty*c.KgQtty/b.KgQtty)
		from #MnfgOutput a
		join (
			select a.DocumentId, a.SiteId, KgQtty=sum(a.KgQtty)
			from #MnfgInput a
			group by a.DocumentId, a.SiteId
			) b on a.DocumentId=b.DocumentId and a.SiteId=b.SiteId
		left join (
			select a.DocumentId, a.SiteId, a.LotNumberWMS, KgQtty=sum(a.KgQtty)
			from #MnfgInput a
			group by a.DocumentId, a.SiteId, a.LotNumberWMS
			) c on a.DocumentId=c.DocumentId and a.SiteId=c.SiteId
		where a.KgQtty<>0
			and a.LotNumberWMS<>c.LotNumberWMS
		group by a.DocumentId, a.SiteId, a.ItemId, a.LotNumberWMS, c.LotNumberWMS, a.Info

		insert into #Manufacturing
			(LotNumber, SourceLotNumber, Info, SourceQtty, Qtty)
		select LotNumberWMS, SourceLotNumberWMS, Info, sum(SourceQtty), sum(Qtty)
		from Manufacturing_ADS a (nolock)
		group by LotNumberWMS, SourceLotNumberWMS, Info

	end  -- DataSources

	-- 1) FLUX UNIFICAT: #Flux

	if object_id('tempdb..#Flux') is not null drop table #Flux;

	create table #Flux (
		SourceLot	nvarchar(36) not null,
		ResultLot	nvarchar(36) not null,
		SourceQtty	float       not null,
		ResultQtty	float       not null,
		Operation	varchar(50) not null)

	-- 1.1) NIR (loturi initiale)
	insert into #Flux 
		(SourceLot, ResultLot, SourceQtty, ResultQtty, Operation)
	select SourceLot=convert(nvarchar(36), i.SourceLotNumber),
		ResultLot=convert(nvarchar(36), i.LotNumber),
		SourceQtty=convert(float, i.SourceQtty),
		ResultQtty=convert(float, i.Qtty),
		Operation='NIR'
	from #Initial i

	-- 1.2) Compunere
	insert into #Flux 
		(SourceLot, ResultLot, SourceQtty, ResultQtty, Operation)
	select SourceLot=convert(nvarchar(36), m.SourceLotNumber),
		ResultLot=convert(nvarchar(36), m.LotNumber),
		SourceQtty=convert(float, m.SourceQtty),
		ResultQtty=convert(float, m.Qtty),
		Operation='Compunere'
	from #Manufacturing m
	where lower(m.Info) like '% compunere%'

	-- 1.3) Descompunere
	insert into #Flux 
		(SourceLot, ResultLot, SourceQtty, ResultQtty, Operation)
	select SourceLot=convert(nvarchar(36), m.SourceLotNumber),
		ResultLot=convert(nvarchar(36), m.LotNumber),
		SourceQtty=convert(float, m.SourceQtty),
		ResultQtty=convert(float, m.Qtty),
		Operation='Descompunere'
	from #Manufacturing m
	where lower(m.Info) like '%descompunere%'

	-- 1.4) Transformare
	insert into #Flux 
		(SourceLot, ResultLot, SourceQtty, ResultQtty, Operation)
	select SourceLot=convert(nvarchar(36), m.SourceLotNumber),
		ResultLot=convert(nvarchar(36), m.LotNumber),
		SourceQtty=convert(float, m.SourceQtty),
		ResultQtty=convert(float, m.Qtty),
		Operation='Transformare'
	from #Manufacturing m
	where lower(m.Info) like '%transformare%'

	-- 2) NETIZARE PE PERECHI: #EdgesNet

	if object_id('tempdb..#EdgesNet') is not null drop table #EdgesNet;

	create table #EdgesNet 
		(SourceLot	nvarchar(36) not null,
		ResultLot	nvarchar(36) not null,
		SourceQtty	float       not null,
		ResultQtty	float       not null,
		EdgeFactor	float       not null)

	-- 2.1) NIR: relatie identitate Lot → Lot, factor 1
	insert into #EdgesNet 
		(SourceLot, ResultLot, SourceQtty, ResultQtty, EdgeFactor)
	select SourceLot,
		ResultLot,
		SourceQtty=sum(SourceQtty),
		ResultQtty=sum(ResultQtty),
		EdgeFactor=1.0
	from #Flux
	where Operation='NIR'
	group by SourceLot, ResultLot;

	-- 2.2) netizare pentru Compunere + Descompunere + Transformare
	;with xNorm as (
		select A=case when f.SourceLot < f.ResultLot then f.SourceLot else f.ResultLot end,
			B=case when f.SourceLot < f.ResultLot then f.ResultLot else f.SourceLot end,
			Sign=case when f.SourceLot < f.ResultLot then 1.0         else -1.0         end,
			SourceQtty=f.SourceQtty,
			ResultQtty=f.ResultQtty
		from #Flux f
		where f.Operation<>'NIR'),
	xPairAgg as (
		select A, B,
			NetSource=sum(Sign * SourceQtty),
			NetResult=sum(Sign * ResultQtty)
		from xNorm
		group by A, B),
	xNetDir as (
		select SourceLot=case when NetResult>=0 then A else B end,
			ResultLot=case when NetResult>=0 then B else A end,
			SourceQtty=case when NetResult>=0 then NetSource  else -NetSource end,
			ResultQtty=case when NetResult>=0 then NetResult  else -NetResult end
		from xPairAgg
		where abs(NetResult)>0.0001)
	insert into #EdgesNet 
		(SourceLot, ResultLot, SourceQtty, ResultQtty, EdgeFactor)
	select SourceLot,
		ResultLot,
		SourceQtty,
		ResultQtty,
		EdgeFactor=case when ResultQtty<>0 then SourceQtty / ResultQtty else 0 end
	from xNetDir
	where SourceQtty>0
		and ResultQtty>0

	-- 3) TRASABILITATE COMPLETa: #ReverseGraph

	if object_id('tempdb..#ReverseGraph') is not null drop table #ReverseGraph;

	;with xTrace as (
		-- nivel 1: muchii directe (citite invers: Final → Initial)
		select InitialLot       =e.SourceLot,
			FinalLot            =e.ResultLot,
			Depth               =1,
			ProportionPer1Final =convert(float, e.EdgeFactor),
			Path                =convert(varchar(max),convert(varchar(36), e.ResultLot)+ '|' +convert(varchar(36), e.SourceLot))
		from #EdgesNet e
		union all
		-- nivele urmatoare: urcam spre loturi mai vechi
		select InitialLot       =e.SourceLot,
			FinalLot            =t.FinalLot,
			Depth               =t.Depth + 1,
			ProportionPer1Final =t.ProportionPer1Final * e.EdgeFactor,
			Path                =t.Path + '|' + convert(varchar(36), e.SourceLot)
		from xTrace t
		join #EdgesNet e on e.ResultLot=t.InitialLot
		where t.Depth < 50
			and t.Path not like '%' + convert(varchar(36), e.SourceLot) + '%')

	select FinalLot,
		InitialLot,
		Depth=min(Depth),
		ProportionPer1Final=sum(ProportionPer1Final)
	into #ReverseGraph
	from xTrace
	group by FinalLot, InitialLot;

	create clustered index IX_ReverseGraph_FinalLot_Initial
		on #ReverseGraph (FinalLot, InitialLot);

	-- 4) Calcule pentru LotBalance_ADS
	truncate table LotBalance_ADS;

	;with xAllLots as (
		select distinct Lot=a.LotNumber
		from #Manufacturing a
		union 
		select distinct Lot=a.SourceLotNumber
		from #Manufacturing a
		union
		select distinct Lot=i.LotNumber
		from #Initial i),
	xProd as (
		-- productie din NIR (prioritar)
		select Lot=i.LotNumber,
			ProducedQtty=sum(i.Qtty)
		from #Initial i
		group by i.LotNumber
		union all
		-- productie din Manufacturing doar daca lotul nu e in NIR
		select Lot=m.LotNumber,
			ProducedQtty=sum(case when lower(m.Info) like '% compunere %'
										or lower(m.Info) like '%transformare%'
								then m.Qtty
								else 0
							end)
		from #Manufacturing m
		where not exists (
			select 1
			from #Initial i
			where i.LotNumber=m.LotNumber)
		group by m.LotNumber),
	xCons as (
		select Lot=m.SourceLotNumber,
			ConsumedQtty=sum(case when lower(m.Info) like '% compunere%' then m.SourceQtty
								when lower(m.Info) like '%transformare%' then m.SourceQtty
								when lower(m.Info) like '%descompunere%' then m.SourceQtty
								else 0
							end)
		from #Manufacturing m
		group by m.SourceLotNumber)

	insert into LotBalance_ADS
		(Lot, ProducedQtty, ConsumedQtty, RemainingQtty, LotType)
	select L.Lot,
		ProducedQtty=isnull(P.ProducedQtty, 0),
		ConsumedQtty=isnull(C.ConsumedQtty, 0),
		RemainingQtty=isnull(P.ProducedQtty, 0) - isnull(C.ConsumedQtty, 0),
		LotType=iif(isnull(P.ProducedQtty, 0) - isnull(C.ConsumedQtty, 0)>0, 'final_vandabil', 'consumat')
	from xAllLots L
	left join xProd P on P.Lot=L.Lot
	left join xCons C on C.Lot=L.Lot;

	-- 5) Calcule pentru LotUsage_ADS (TRASABILITATE REALa)
	truncate table LotUsage_ADS;

	-- 5.1) Loturi finale vandabile
	;with xFinalLots as (
		select Lot, ProducedQtty, ConsumedQtty
		from LotBalance_ADS (nolock)
		where RemainingQtty>0),

	-- 5.2) Muchii de productie (RAPORT COMPUNERE WMS)
	xProdEdges as (
		select
			InitialLot =rg.InitialLot,
			FinalLot   =m.LotNumber,
			ProducedQtty=sum(convert(float, m.Qtty)),
			InitialConsumedQtyReal=sum(convert(float, m.SourceQtty)),
			FactorTech=sum(convert(float, m.SourceQtty))/nullif(sum(convert(float, m.Qtty)),0)
		from #Manufacturing m
		join #ReverseGraph rg on rg.FinalLot = m.SourceLotNumber
		where lower(m.Info) like '% compunere%'
		and rg.Depth >= 1
		group by rg.InitialLot, m.LotNumber),
	xDirectProd as (
		select p.FinalLot,
			p.InitialLot,
			Depth     =1,
			p.FactorTech,
			p.ProducedQtty,
			p.InitialConsumedQtyReal
		from xProdEdges p
		join xFinalLots f on f.Lot=p.FinalLot),

	-- 5.3) Transformari (alias intre loturi)
	xTransformMap as (
		select FromLot	=m.SourceLotNumber,
			ToLot		=m.LotNumber
		from #Manufacturing m
		where lower(m.Info) like '%transformare%'),
	xAliasChain as (
		select Lot=Lot,
			RootLot=Lot,
			Depth  =0
		from xFinalLots
		union all
		select t.FromLot,
			a.RootLot,
			a.Depth + 1
		from xAliasChain a
		join xTransformMap t on t.ToLot=a.Lot
		where a.Depth < 5),
	xFinalMapped as (
		-- lot cu productie directa
		select distinct FinalLot=f.Lot,
			RootFinalLot=f.Lot
		from xFinalLots f
		where exists (
			select 1 from xDirectProd d where d.FinalLot=f.Lot)
		union
		-- lot fara compunere directa → ia producatorul prin transformare
		select distinct FinalLot=f.Lot,
			RootFinalLot=a.RootLot
		from xFinalLots f
		join xAliasChain a on a.Lot=f.Lot
		where not exists (
			select 1 from xDirectProd d where d.FinalLot=f.Lot)),
	xFinalEdges as (
		select fm.FinalLot,
			d.InitialLot,
			d.FactorTech,
			d.ProducedQtty,
			d.InitialConsumedQtyReal
		from xFinalMapped fm
		join xDirectProd d on d.FinalLot=fm.RootFinalLot),
	xSumProd as (
		select FinalLot,
			TotalProducedQtty=sum(ProducedQtty)
		from xFinalEdges
		group by FinalLot),
	xCalc as (
		select e.FinalLot,
			e.InitialLot,
			Depth               =1,
			ProportionPer1Final =e.FactorTech,
			ProducedQtty        =e.ProducedQtty,
			PctOfFinalLot       =e.ProducedQtty / nullif(sp.TotalProducedQtty, 0),
			InitialConsumedQty  =e.InitialConsumedQtyReal
		from xFinalEdges e
		join xSumProd sp on sp.FinalLot=e.FinalLot)
	insert into LotUsage_ADS 
		(FinalLot, InitialLot, Depth, InitialConsumedQty, FinalObtainedQty, ProportionPer1Final, PctOfFinalLot)
	select FinalLot,
		InitialLot,
		Depth,
		InitialConsumedQty   =round(InitialConsumedQty,6),
		FinalObtainedQty     =round(ProducedQtty,6),
		ProportionPer1Final  =round(ProportionPer1Final,6),
		PctOfFinalLot        =round(PctOfFinalLot,6)
	from xCalc;

	-- 5.4) Loturi rezultate doar din TRANSFORMARE
	;with xTransformLots as (
		select distinct FinalLot =m.LotNumber,
			ParentLot=m.SourceLotNumber
		from #Manufacturing m
		join LotBalance_ADS lb (nolock) on lb.Lot=m.LotNumber
		where lower(m.Info) like '%transformare%'
		  and lb.RemainingQtty>0
		  and not exists (
				select 1
				from #Manufacturing c
				where c.LotNumber=m.LotNumber
				  and lower(c.Info) like '% compunere%')),
	xScale as (
		select t.FinalLot,
			t.ParentLot,
			Alpha=iif(p.ProducedQtty=0, 0, c.ProducedQtty / p.ProducedQtty)
		from xTransformLots t
		join LotBalance_ADS p (nolock) on p.Lot=t.ParentLot
		join LotBalance_ADS c (nolock) on c.Lot=t.FinalLot),
	xParentUsage as (
		select s.FinalLot,
			s.ParentLot,
			s.Alpha,
			u.InitialLot,
			u.Depth,
			u.InitialConsumedQty,
			u.FinalObtainedQty,
			u.ProportionPer1Final,
			u.PctOfFinalLot
		from xScale s
		join LotUsage_ADS u (nolock) on u.FinalLot=s.ParentLot)
	insert into LotUsage_ADS 
		(FinalLot, InitialLot, Depth, InitialConsumedQty, FinalObtainedQty, ProportionPer1Final, PctOfFinalLot)
	select FinalLot        =p.FinalLot,
		InitialLot         =p.InitialLot,
		Depth              =p.Depth + 1,
		InitialConsumedQty =round(p.InitialConsumedQty*p.Alpha,6),
		FinalObtainedQty   =round(p.FinalObtainedQty*p.Alpha,6),
		ProportionPer1Final=round(p.ProportionPer1Final,6),
		PctOfFinalLot      =round(p.PctOfFinalLot,6)
	from xParentUsage p;

	-- 5.5) Completam LotUsage_ADS cu loturile fara traseu (NIR, consumate etc.)
	;with xMissingLots as (
		select FinalLot        =b.Lot,
			InitialLot         =b.Lot,
			Depth              =0,
			InitialConsumedQty =0.0,
			FinalObtainedQty   =isnull(b.ProducedQtty, 0),
			ProportionPer1Final=1.0,
			PctOfFinalLot      =1.0
		from LotBalance_ADS b (nolock)
		where not exists (
			select 1
			from LotUsage_ADS u (nolock)
			where u.FinalLot=b.Lot))

	insert into LotUsage_ADS 
		(FinalLot, InitialLot, Depth, InitialConsumedQty,
		FinalObtainedQty, ProportionPer1Final, PctOfFinalLot)
	select FinalLot, InitialLot, Depth, round(InitialConsumedQty,6), 
		round(FinalObtainedQty,6), round(ProportionPer1Final,6), round(PctOfFinalLot,6)
	from xMissingLots

select *
from #ReverseGraph
where FinalLot = '4BED0DDD-1725-4255-8EF5-4E0500B26F91'
order by InitialLot, Depth

select *
from #ReverseGraph
where InitialLot = '58DD2A97-CC5B-4E55-B62A-8A99D0709683'
order by FinalLot, Depth

	drop table if exists #Initial, #MnfgInput, #MnfgOutput, #Manufacturing, #Flux, #EdgesNet, #ReverseGraph
end
go

