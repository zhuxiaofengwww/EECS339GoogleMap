//
// Global state
//
// map     - the map object
// usermark- marks the user's position on the map
// markers - list of markers on the current map (not including the user position)
// 
//

//
// First time run: request current location, with callback to Start
//
if (navigator.geolocation)  {
    navigator.geolocation.getCurrentPosition(Start);
}


function UpdateMapById(id, tag) {
    var target = document.getElementById(id);
    //Guarding for unnecessary map change if there is no target. 
    if(target==null) return;
    var data = target.innerHTML;

    var rows  = data.split("\n");
   
    for (i in rows) {
	var cols = rows[i].split("\t");
	var lat = cols[0];
	var long = cols[1];

	markers.push(new google.maps.Marker({ map:map,
						    position: new google.maps.LatLng(lat,long),
						    title: tag+"\n"+cols.join("\n")}));
    }
}

function ClearMarkers()
{
    // clear the markers
    while (markers.length>0) { 
	markers.pop().setMap(null);
    }
}


function UpdateMap()
{
    var color = document.getElementById("color");
    
    color.innerHTML="<b><blink>Updating Display...</blink></b>";
    color.style.backgroundColor='white';

    //ViewShift();
    ClearMarkers();
   // var checkedValue = 
   //
   //
    if(document.getElementById("checkCommittee")){
    if(document.getElementById("checkCommittee").checked){ 
    UpdateMapById("committee_data","COMMITTEE");
    }
    }
    if(document.getElementById("checkCandidate")){
    if(document.getElementById("checkCandidate").checked){
    UpdateMapById("candidate_data","CANDIDATE");
    }    	
    }
    if(document.getElementById("checkIndividual")){
    if(document.getElementById("checkIndividual").checked){
    UpdateMapById("individual_data", "INDIVIDUAL");
    }
    }
    if(document.getElementById("checkOpinion")){
    if(document.getElementById("checkOpinion").checked){
    UpdateMapById("opinion_data","OPINION");
    }}
    color.innerHTML="Ready";
    
    if (Math.random()>0.5) { 
	color.style.backgroundColor='blue';
    } else {
	color.style.backgroundColor='red';
    }

}

function NewData(data)
{
  var target = document.getElementById("data");
  
  target.innerHTML = data;

  UpdateMap();

}

function ViewShift()
{
    var bounds = map.getBounds();

    var ne = bounds.getNorthEast();
    var sw = bounds.getSouthWest();

    var color = document.getElementById("color");

    color.innerHTML="<b><blink>Querying...("+ne.lat()+","+ne.lng()+") to ("+sw.lat()+","+sw.lng()+")</blink></b>";
    color.style.backgroundColor='white';
    var what = "";
    if(document.getElementById("checkCommittee")){
    if(document.getElementById("checkCommittee").checked){
        if(what.length==0){
         what = what + "committees";   
        }
        else{
        what = what +  ",committees";
        }
    }
    }
    
    if(document.getElementById("checkCandidate")){
    if(document.getElementById("checkCandidate").checked){
        if(what.length==0){
        what = "candidates";
        }
        else{
            what = what + ",candidates";
        }
    }    	
    }
    
    if(document.getElementById("checkIndividual")){
    if(document.getElementById("checkIndividual").checked){
        if(what.length==0){
     what = "individuals";   
    }
    else{
       what = what+",individuals";
    }
    }
    }
    
    
    if(document.getElementById("checkOpinion")){
    if(document.getElementById("checkOpinion").checked){
        if(what.length==0){
            what = "opinions";
        }
        else{
            what = what+",opinions";
        }
    }
    }
    if(document.getElementById("agg")){
        if(document.getElementById("agg").checked){
            if(what.length==0){
                what = "agg";
            }
            else{
                what = what + ",agg";
            }
        }
    }
    // debug status flows through by cookie
    //
    console.log("what array is : " +what);
  //  $.get("rwb.pl?act=near&latne="+ne.lat()+"&longne="+ne.lng()+"&latsw="+sw.lat()+"&longsw="+sw.lng()+"&cycle="+getCycles()+"&format=raw&what="+what, NewData);
    var cycles = getCycles();
    if(cycles.length<1){
    console.log("this is the last checkbox");
    
    if(document.getElementById(1112)){    
    document.getElementById(1112).checked=true;    
    window.alert("you are deselecting all cycles. Resetting cycle to 1112"); 
    }}
    $.get("rwb.pl?act=near&latne="+ne.lat()+"&longne="+ne.lng()+"&latsw="+sw.lat()+"&longsw="+sw.lng()+"&cycle="+getCycles()+"&format=raw&what="+what, NewData);
    UpdateMap();
}

function getCycles()
{

 var cyclesString = "";
  $('input:checkbox:checked.cycles').each(function(){
      if(cyclesString.length == 0){
        cyclesString = "\'"+$(this).val()+"\'";
      }
      else{
       cyclesString= cyclesString+",\'"+$(this).val()+"\'"; 
        }
    });
console.log("cyclesArray: "+cyclesString);
return cyclesString;
}

function Reposition(pos)
{
    var lat=pos.coords.latitude;
    var long=pos.coords.longitude;

    map.setCenter(new google.maps.LatLng(lat,long));
    usermark.setPosition(new google.maps.LatLng(lat,long));
}


function Start(location) 
{
  var lat = location.coords.latitude;
  var long = location.coords.longitude;
  var acc = location.coords.accuracy;
  
  var mapc = $( "#map");

  map = new google.maps.Map(mapc[0], 
			    { zoom:16, 
				center:new google.maps.LatLng(lat,long),
				mapTypeId: google.maps.MapTypeId.HYBRID
				} );
  document.cookie="latitude="+lat;
  document.cookie="longitude="+long;
  usermark = new google.maps.Marker({ map:map,
					    position: new google.maps.LatLng(lat,long),
					    title: "You are here"});

  markers = new Array;

  var color = document.getElementById("color");
  color.style.backgroundColor='white';
  color.innerHTML="<b><blink>Waiting for first position</blink></b>";

  google.maps.event.addListener(map,"bounds_changed",ViewShift);
  google.maps.event.addListener(map,"center_changed",ViewShift);
  google.maps.event.addListener(map,"zoom_changed",ViewShift);

  navigator.geolocation.watchPosition(Reposition);

}


