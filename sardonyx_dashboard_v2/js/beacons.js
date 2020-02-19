
const dateFormatSpecifier = '%Y-%m-%d';
const dateFormat = d3.timeFormat(dateFormatSpecifier);
const dateFormatParser = d3.timeParse(dateFormatSpecifier);

let regionSelector = dc.selectMenu("#region-selector");
let categoryChart = dc.pieChart('#category-piechart');
let environmentChart = dc.rowChart('#beacons-environment-rowchart');
let activationChart = dc.rowChart('#activation-rowchart');
let typeChart = dc.rowChart('#type-rowchart');
let monthlySeries = dc.lineChart('#incident-series');
let mapChart = dc_leaflet.markerChart("#map-chart");


monthlySeries.margins().left = 40;


d3.csv('../../Portals/4/SARDonyx/data/beacons_data.csv').then(function (data) {
  data.forEach(function (d) {
        d.Lat = +d.Lat;
        d.Long = +d.Long;
        d.date = dateFormatParser(d.date);
        d.date2 = dateFormat(d.date);
        d.month = d3.timeMonth(d.date);
        d.geo = d.Lat + "," + d.Long;
    });

  console.log(data);

  /* now we create the crossfilter and set up the dimensions and groups*/
  let ndx = crossfilter(data);
  let all = ndx.groupAll();


  /* create a dimension for monthly incidents */
  let regionDimension = ndx.dimension(function (d) {
        return d.Region;
    });

  let regionDimensionGroup = regionDimension.group();

  /* create a dimension for monthly incidents */
  let monthlyDimension = ndx.dimension(function (d) {
        return d.month;
    });

  let monthlyDimensionGroup = monthlyDimension.group();

  /* create a dimension for SAR Category */
  let categoryDimension = ndx.dimension(function (d) {
        return d.SarCategory;
    });

  let categoryDimensionGroup = categoryDimension.group();



  /* create a dimension for Activation reason */
  let activationDimension = ndx.dimension(function (d) {
        return d.Activation;
    });

  let activationDimensionGroup = activationDimension.group();


  /* create a dimension for Response type */
  let typeDimension = ndx.dimension(function (d) {
        return d.Type;
    });

  let typeDimensionGroup = typeDimension.group();


  /* create a dimension for Environment */
  let environmentDimension = ndx.dimension(function (d) {
        return d.Environment;
    });

  let environmentDimensionGroup = environmentDimension.group();


  /* create a dimension for map data */
  let mapDimension = ndx.dimension(function (d) {
        return d.geo;
    });

  let mapDimensionGroup = mapDimension.group().reduce(
          function(p, v) {
              // p.Environment = v.Environment;
              p.SarCategory = v.SarCategory;
              ++p.count;
              return p;
          },
          function(p, v) {
              --p.count;
              return p;
          },
          function() {
              return {count: 0};
          }
      );

  // create region regionSelector
  regionSelector
    .dimension(regionDimension)
    .group(regionDimensionGroup);



  /* build pie chart for Categories*/
  categoryChart
    .width(180)
    .height(180)
    .radius(null)
    .dimension(categoryDimension)
    .group(categoryDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true);



  /* build row chart for Environments*/
  environmentChart
    .width(250)
    .height(200)
    .dimension(environmentDimension)
    .group(environmentDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true)
    .elasticX(true)
    .xAxis().ticks(5);

  environmentChart.margins().left = 15;
  environmentChart.margins().right = 15;


  /* build row chart for Responses*/
  activationChart
    .width(250)
    .height(200)
    .dimension(activationDimension)
    .group(activationDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true)
    .elasticX(true)
    .xAxis().ticks(3);

  activationChart.margins().left = 15;
  activationChart.margins().right = 20;
  activationChart.margins().top = 10;

  /* build row chart for Responses*/
  typeChart
    .width(250)
    .height(200)
    .dimension(typeDimension)
    .group(typeDimensionGroup)
    .transitionDuration(500)
    .controlsUseVisibility(true)
    .elasticX(true)
    .xAxis().ticks(5);

  typeChart.margins().left = 15;
  typeChart.margins().right = 15;
  typeChart.margins().top = 10;


  /* build line chart for time series*/
  monthlySeries
    .height(150)
    .dimension(monthlyDimension)
    .group(monthlyDimensionGroup)
    .x(d3.scaleTime().domain(d3.extent(data, function(d) {
          return new Date(d.date);
        })))
    .transitionDuration(500)
    .elasticY(true)
    .controlsUseVisibility(true)
    .yAxisLabel("Incident count");

  mapChart
    .dimension(mapDimension)
	  .group(mapDimensionGroup)
	  .valueAccessor(d => d.value.count)
	  .center([-40.77,173.59])
	  .zoom(5)
	  .renderPopup(false)
	  .brushOn(true)
	  .cluster(true)
	  .filterByArea(true)
	  .controlsUseVisibility(true)
    .icon(function(d) {
              var iconUrl;
              switch(d.value.Environment) {
              case 'Air':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-violet.png';
                  break;
              case 'Marine':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-blue.png';
                  break;
              case 'Land':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-green.png';
                  break;
              case 'Undetermined':
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-grey.png';
                  break;
              default:
                  iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png';
              }
              return new L.Icon({
                  iconUrl: iconUrl,
                  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png'
              });
          });
    // .icon(function(d) {
    //           var iconUrl;
    //           switch(d.value.SarCategory) {
    //           case 'Cat1':
    //               iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-violet.png';
    //               break;
    //           case 'Cat2':
    //               iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-blue.png';
    //               break;
    //           default:
    //               iconUrl = 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png';
    //           }
    //           return new L.Icon({
    //               iconUrl: iconUrl,
    //               // shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png'
    //           });
    //       });

  dc.override(mapChart, 'redraw', function() {
          window.setTimeout(() => mapChart._redraw(), 500);
      });

  // used to reset the map
  // $("#mapReset").on('click', function() {
	// 	mapChart.map().setView([-40.77,173.59], 3);
	//  });

   // date picker function for the sidebar
   $(function() {
     $(".date-picker").datepicker({
       dateFormat: "yy-mm-dd"
     });
   });



   // set behaviour for the date pickers
   // these will set the ranges on the monthly series
   $("#datepicker-from").on('change', function() {
     let date_from = $("#datepicker-from").datepicker("getDate");
     let date_to = $("#datepicker-to").datepicker("getDate");

     if(date_from && date_to){
       monthlyDimension.filterRange([date_from, date_to]);
       monthlySeries.filter(dc.filters.RangedFilter(date_from, date_to));
       dc.redrawAll();
     }
    });

   $("#datepicker-to").on('change', function() {
     let date_from = $("#datepicker-from").datepicker("getDate");
     let date_to = $("#datepicker-to").datepicker("getDate");

     if(date_from && date_to){
       monthlyDimension.filterRange([date_from, date_to]);
       monthlySeries.filter(dc.filters.RangedFilter(date_from, date_to));
       dc.redrawAll();
     }
    });


    // if the monthly series chart is filtered we want to show the
    // current date filter values in the date picker widgets
    monthlySeries.on("filtered", function(chart){
      let filters = chart.filters();
      if(filters.length > 0){
        let range = filters[0];
        $('#datepicker-from').datepicker("setDate", range[0] );
        $('#datepicker-to').datepicker("setDate", range[1] );
      } else {
        let dateExtent = d3.extent(data, function(d) { return d.date2; });
        $('#datepicker-from').datepicker("setDate", dateExtent[0] );
        $('#datepicker-to').datepicker("setDate", dateExtent[1] );
      }
    });




  dc.renderAll();

  dc.redrawAll();

});
