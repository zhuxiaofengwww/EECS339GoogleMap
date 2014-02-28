#!/usr/bin/perl -w

#
#
# rwb.pl (Red, White, and Blue)
#
#
# Example code for EECS 339, Northwestern University
#
#
#

# The overall theory of operation of this script is as follows
#
# 1. The inputs are form parameters, if any, and a session cookie, if any. 
# 2. The session cookie contains the login credentials (User/Password).
# 3. The parameters depend on the form, but all forms have the following three
#    special parameters:
#
#         act      =  form  <the form in question> (form=base if it doesn't exist)
#         run      =  0 Or 1 <whether to run the form or not> (=0 if it doesn't exist)
#         debug    =  0 Or 1 <whether to provide debugging output or not> 
#
# 4. The script then generates relevant html based on act, run, and other 
#    parameters that are form-dependent
# 5. The script also sends back a new session cookie (allowing for logout functionality)
# 6. The script also sends back a debug cookie (allowing debug behavior to propagate
#    to child fetches)
#


#
# Debugging
#
# database input and output is paired into the two arrays noted
#
my $debug=0; # default - will be overriden by a form parameter or cookie
my @sqlinput=();
my @sqloutput=();
# Edit by Xiaofengzhu
my $edit_content="I'd like you to accept this invition to RWB using the following link. Thank you! ";
my $link="http://murphy.wot.eecs.northwestern.edu/~xzm603/rwb/rwb.pl?act=activate-user&token=";
my $title="Invition_from_RWB_by";
my $newpermission="";
my $subject;
my $content;

my %labels = (
'red' => 'Red',
'white' => 'White',
'blue' => 'Blue');
# Edit by Xiaofengzhu

#
# The combination of -w and use strict enforces various
# rules that make the script more resilient and easier to run
# as a CGI script.
#
use strict;

# The CGI web generation stuff
# This helps make it easy to generate active HTML content
# from Perl
#
# We'll use the "standard" procedural interface to CGI
# instead of the OO default interface
use CGI qw(:standard);

# Edit by Xiaofengzhu
use Digest::SHA1;
# Edit by Xiaofengzhu


# The interface to the database.  The interface is essentially
# the same no matter what the backend database is.  
#
# DBI is the standard database interface for Perl. Other
# examples of such programatic interfaces are ODBC (C/C++) and JDBC (Java).
#
#
# This will also load DBD::Oracle which is the driver for
# Oracle.
use DBI;

#
#
# A module that makes it easy to parse relatively freeform
# date strings into the unix epoch time (seconds since 1970)
#
use Time::ParseDate;



#
# You need to override these for access to your database
#
my $dbuser="xzm603";
my $dbpasswd="z5tf3jqBZ";


#
# The session cookie will contain the user's name and password so that 
# he doesn't have to type it again and again. 
#
# "RWBSession"=>"user/password"
#
# BOTH ARE UNENCRYPTED AND THE SCRIPT IS ALLOWED TO BE RUN OVER HTTP
# THIS IS FOR ILLUSTRATION PURPOSES.  IN REALITY YOU WOULD ENCRYPT THE COOKIE
# AND CONSIDER SUPPORTING ONLY HTTPS
#
my $cookiename="RWBSession";
#
# And another cookie to preserve the debug state
#
my $debugcookiename="RWBDebug";

#
# Get the session input and debug cookies, if any
#
my $inputcookiecontent = cookie($cookiename);
my $inputdebugcookiecontent = cookie($debugcookiename);

my $ur;
my $pwd;
($ur,$pwd) = split(/\//,$inputcookiecontent);
my $salt = 'ab';
my $cryptedpwd = crypt $pwd, $salt;
$inputcookiecontent=join("/",$ur,$cryptedpwd);
#
# Will be filled in as we process the cookies and paramters
#
my $outputcookiecontent = undef;
my $outputdebugcookiecontent = undef;
my $deletecookie=0;
my $user = undef;
my $password = undef;
my $logincomplain=0;

#
# Get the user action and whether he just wants the form or wants us to
# run the form
#
my $action;
my $run;


if (defined(param("act"))) { 
    $action=param("act");
    if (defined(param("run"))) { 
        $run = param("run") == 1;
    } else {
        $run = 0;
    }
} else {
    $action="base";
    $run = 1;
}

my $dstr;

if (defined(param("debug"))) { 
# parameter has priority over cookie
    if (param("debug") == 0) { 
        $debug = 0;
    } else {
        $debug = 1;
    }
} else {
    if (defined($inputdebugcookiecontent)) { 
        $debug = $inputdebugcookiecontent;
    } else {
# debug default from script
    }
}

$outputdebugcookiecontent=$debug;

#
#
# Who is this?  Use the cookie or anonymous credentials
#
#
if (defined($inputcookiecontent)) { 
# Has cookie, let's decode it
    ($user,$password) = split(/\//,$inputcookiecontent);
    $outputcookiecontent = $inputcookiecontent;
} else {
# No cookie, treat as anonymous user
    ($user,$password) = ("anon","anonanon");
}

#
# Is this a login request or attempt?
# Ignore cookies in this case.
#
if ($action eq "login") { 
    if ($run) { 
#
# Login attempt
#
# Ignore any input cookie.  Just validate user and
# generate the right output cookie, if any.
#
        ($user,$pwd) = (param('user'),param('password'));
        my $salt = 'ab';
        my $password = crypt $pwd, $salt;
        if (ValidUser($user,$password)) { 
# if the user's info is OK, then give him a cookie
# that contains his username and password 
# the cookie will expire in one hour, forcing him to log in again
# after one hour of inactivity.
# Also, land him in the base query screen
            $outputcookiecontent=join("/",$user,$password);
            $action = "base";
            $run = 1;
        } else {
# uh oh.  Bogus login attempt.  Make him try again.
# don't give him a cookie
            $logincomplain=1;
            $action="login";
            $run = 0;
        }
    } else {
#
# Just a login screen request, but we should toss out any cookie
# we were given
#
        undef $inputcookiecontent;
        ($user,$password)=("anon","anonanon");
    }
} 


#
# If we are being asked to log out, then if 
# we have a cookie, we should delete it.
#
if ($action eq "logout") {
    $deletecookie=1;
    $action = "base";
    $user = "anon";
    $password = "anonanon";
    $run = 1;
}


my @outputcookies;

#
# OK, so now we have user/password
# and we *may* have an output cookie.   If we have a cookie, we'll send it right 
# back to the user.
#
# We force the expiration date on the generated page to be immediate so
# that the browsers won't cache it.
#
if (defined($outputcookiecontent)) { 
    my $cookie=cookie(-name=>$cookiename,
            -value=>$outputcookiecontent,
            -expires=>($deletecookie ? '-1h' : '+1h'));
    push @outputcookies, $cookie;
} 
#
# We also send back a debug cookie
#
#
if (defined($outputdebugcookiecontent)) { 
    my $cookie=cookie(-name=>$debugcookiename,
            -value=>$outputdebugcookiecontent);
    push @outputcookies, $cookie;
}

#
# Headers and cookies sent back to client
#
# The page immediately expires so that it will be refetched if the
# client ever needs to update it
#
print header(-expires=>'now', -cookie=>\@outputcookies);

#
# Now we finally begin generating back HTML
#
#
#print start_html('Red, White, and Blue');
print "<html style=\"height: 100\%\">";
print "<head>";
print "<title>Red, White, and Blue</title>";
print "</head>";

print "<body style=\"height:100\%;margin:0\">";

#
# Force device width, for mobile phones, etc
#
#print "<meta name=\"viewport\" content=\"width=device-width\" />\n";

# This tells the web browser to render the page in the style
# defined in the css file
#
print "<style type=\"text/css\">\n\@import \"rwb.css\";\n</style>\n";


print "<center>" if !$debug;

#
#
# The remainder here is essentially a giant switch statement based
# on $action. 
#
#
#


# LOGIN
#
# Login is a special case since we handled running the filled out form up above
# in the cookie-handling code.  So, here we only show the form if needed
# 
#
if ($action eq "login") { 
    if ($logincomplain) { 
        print "Login failed.  Try again.<p>"
    } 
    if ($logincomplain or !$run) { 
        print start_form(-name=>'Login'),
              h2('Login to Red, White, and Blue'),
              "Name:",textfield(-name=>'user'),	p,
              "Password:",password_field(-name=>'password'),p,
              hidden(-name=>'act',default=>['login']),
              hidden(-name=>'run',default=>['1']),
              submit,
              end_form;
    }
}



#
# BASE
#
# The base action presents the overall page to the browser
#
#
#
if ($action eq "base") { 
#
# Google maps API, needed to draw the map
#
    print "<script src=\"http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js\" type=\"text/javascript\"></script>";
    print "<script src=\"http://maps.google.com/maps/api/js?sensor=false\" type=\"text/javascript\"></script>";

#
# The Javascript portion of our app
#
    print "<script type=\"text/javascript\" src=\"rwb.js\"> </script>";



#
#
# And something to color (Red, White, or Blue)
#
    print "<div id=\"color\" style=\"width:100\%; height:10\%\"></div>";

#
#
# And a map which will be populated later
#
    print "<div id=\"map\" style=\"width:100\%; height:80\%\"></div>";

#aggregated view of summaries from commettee, Candidate, opinions or individual. 
#
# if the user has committees selected, then compute the total amount of money involved by the
#  committees in the current view. The cs339.comm_to_cand and cs339.comm_to_comm tables contain
#  such information. Color the background of this summary with a color from blue to red based on the
#  difference between contributions to the Democratic and Republican parties
# And a div to populate with info about nearby stuff
#
#
    if ($debug) {
# visible if we are debugging
        print "<div id=\"data\" style=\:width:100\%; height:10\%\"></div>";
    } else {
# invisible otherwise
        print "<div id=\"data\" style=\"display: none;\"></div>";
    }


# height=1024 width=1024 id=\"info\" name=\"info\" onload=\"UpdateMap()\"></iframe>";
#here prints out the checkboxes for user to choose what data to show. 
#Dinamically grab the available cycles from the db. 




#
# User mods
#
#
    if ($user eq "anon") {
        print "<p>You are anonymous, but you can also <a href=\"rwb.pl?act=login\">login</a></p>";
    } else {


        print "<input type=checkbox name=\"committee\" value=committee id=checkCommittee onchange = \"ViewShift()\" checked>show committee data<br>";
        print "<input type=checkbox name=\"candidate\" value=candidate id=checkCandidate onchange = \"ViewShift()\" checked>show candidate data<br>";
        print "<input type=checkbox name=individual value=individual id=checkIndividual onchange = \"ViewShift()\" >show individual data<br>";
        if(UserCan($user,"give-opinion-data")){
            print "<input type=checkbox name=opinion value=opinion id=checkOpinion onchange = \"ViewShift()\" >show opinion data<br>";
        }
        print "<input type=checkbox name=\"agg\" value= agg id=agg onchange=\"ViewShift()\">show aggregated view<br>";
        print "<input type=checkbox name=\"ec3\" value= ec3 id=ec3 onchange=\"ViewShift()\">show extra credit3 view<br>";
        my @input_cycles = ExecSQL($dbuser, $dbpasswd, "select distinct(cycle) from cs339.committee_master order by cycle",undef); 
        my $i=0;
        for $i ( 0 .. $#input_cycles ){
            if($input_cycles[$i][0]==1112){
                print "<input type=checkbox class=\"cycles\" id=1112 value=$input_cycles[$i][0]  onchange = \"ViewShift()\" checked>$input_cycles[$i][0] data<br>";
            }
            else{
                print "<input type=checkbox class=\"cycles\" value=$input_cycles[$i][0]  onchange = \"ViewShift()\" >$input_cycles[$i][0] data<br>";
            }
        }

        print "<p>You are logged in as $user and can do the following:</p>";
        if (UserCan($user,"give-opinion-data")) {
            print "<p><a href=\"rwb.pl?act=give-opinion-data\">Give Opinion Of Current Location</a></p>";
        }
        if (UserCan($user,"give-cs-ind-data")) {
            print "<p><a href=\"rwb.pl?act=give-cs-ind-data\">Geolocate Individual Contributors</a></p>";
        }
#todo: u need more parameters  $latne $longne $latsw $longsw $whatparam $format $cycle


        if (UserCan($user,"manage-users") || UserCan($user,"invite-users")) {
            print "<p><a href=\"rwb.pl?act=invite-user\">Invite User</a></p>";
        }
        if (UserCan($user,"manage-users") || UserCan($user,"add-users")) { 
            print "<p><a href=\"rwb.pl?act=add-user\">Add User</a></p>";
        } 
        if (UserCan($user,"manage-users")) { 
            print "<p><a href=\"rwb.pl?act=delete-user\">Delete User</a></p>";
            print "<p><a href=\"rwb.pl?act=add-perm-user\">Add User Permission</a></p>";
            print "<p><a href=\"rwb.pl?act=revoke-perm-user\">Revoke User Permission</a></p>";
        }
        print "<p><a href=\"rwb.pl?act=logout&run=1\">Logout</a></p>";
    }

}

#
#
# NEAR
#
#
# Nearby committees, candidates, individuals, and opinions
#
#
# Note that the individual data should integrate the FEC data and the more
# precise crowd-sourced location data.   The opinion data is completely crowd-sourced
#
# This form intentionally avoids decoration since the expectation is that
# the client-side javascript will invoke it to get raw data for overlaying on the map
#
#
#
#
#
if ($action eq "near") {

    my $latne = param("latne");
    my $longne = param("longne");
    my $latsw = param("latsw");
    my $longsw = param("longsw");
    my $whatparam = param("what");
    my $format = param("format");
    my $cycle = param("cycle");
#   $cycle = "1112";
    my %what;
    $format = "table" if !defined($format);
    $cycle = "1112" if !defined($cycle);
    if (!defined($whatparam) || $whatparam eq "all") { 
        %what = ( committees => 1, 
                candidates => 1,
                individuals =>1,
                opinions => 1);
    } else {
        map {$what{$_}=1} split(/\s*,\s*/,$whatparam);
    }


    if ($what{committees}) { 
        my ($str,$error) = Committees($latne,$longne,$latsw,$longsw,$cycle,$format);
        if($what{agg}){
            aggCommittees($latne,$longne,$latsw,$longsw,$cycle,$format);
        }
        if (!$error) {
            if ($format eq "table") { 
                print "<h2>Nearby committees</h2>$str";
            } else {
                print $str;
            }
        }
    }
    if ($what{candidates}) {
        my ($str,$error) = Candidates($latne,$longne,$latsw,$longsw,$cycle,$format);
        if($what{agg}){
            aggCandidates($latne,$longne,$latsw,$longsw,$cycle,$format);
        }
        if (!$error) {
            if ($format eq "table") { 
                print "<h2>Nearby candidates</h2>$str";
            } else {
                print $str;
            }
        }
    }
    if ($what{individuals}) {
        my ($str,$error) = Individuals($latne,$longne,$latsw,$longsw,$cycle,$format);
        if($what{agg}){
            aggIndividuals($latne,$longne,$latsw,$longsw,$cycle,$format);
        }        
        if (!$error) {
            if ($format eq "table") { 
                print "<h2>Nearby individuals</h2>$str";
            } else {
                print $str;
            }
        }
    }
    if ($what{opinions}) {
        my ($str,$error) = Opinions($latne,$longne,$latsw,$longsw,$cycle,$format);

        if($what{agg}){
            aggOpinions($latne,$longne,$latsw,$longsw,$cycle,$format);
        }
        if (!$error) {
            if ($format eq "table") { 
                print "<h2>Nearby opinions</h2>$str";
            } else {
                print $str;
            }
        }
    }
    if($what{ec3}){
   #show ec3 view
           print "<div>";
           print ec3($latne,$longne,$latsw,$longsw,$cycle,$format);
           print "</div>";
    }
}
#Edit by XiaofengZhu
if ($action eq "invite-user") {
    if (!UserCan($user,"invite-users") && !UserCan($user,"manage-users")) {
        print h2('You do not have the required permissions to invite users.');
    } else {
        if (!$run) {
            print start_form(-name=>'InviteUser'),
            h2('Invite User'),
            "Name: ", textfield(-name=>'name'),
            p,
            "Email: ", textfield(-name=>'email'),
            p,
            "Grant permissions to this user: ",
            p;
            my @permissions = ExecSQL($dbuser, $dbpasswd, "select action from rwb_permissions where name='$user' order by action",undef);
            # my @permissions =GetRefererPerm($user);
            my $i=0;
            # if($#permissions>0){
            for $i ( 0 .. $#permissions ){
                
                print "<input type=checkbox name='permission_checkbox' value=$permissions[$i][0]  >$permissions[$i][0]<br>";
            }
            # }else{
            #  print "You do not have any permissions";
            # }
            print
            p,
            hidden(-name=>'run',-default=>['1']),
            hidden(-name=>'act',-default=>['invite-user']),
            submit,
            end_form,
            hr;
        } else {
            my $name=param('name');
            my $email=param('email');
            my @permissionC=param('permission_checkbox');
            
            #     my $error;
            #     $error=CreateInviteTemp();
            #     if ($error) {
            # print "Can't create invite_temp because: $error";
            #     } else {
            # print "create invite_temp successfully $user\n";
            #     }
            my $timestamp = localtime(time);
            my $add_content =join("",$email,$timestamp);
            my $sha1 = Digest::SHA1->new;
            $sha1->add($add_content);
            my $token = $sha1->hexdigest;
            my $send;
            
            if(@permissionC){
                $newpermission=join("\n","You will have the following permissions:",@permissionC);
            }
            $content=join("","Hi ",$name,",\n\n",$edit_content,"\n",$newpermission,"\n",$link,$token,"\n\n","Cheers,\n",$user);
            
            $subject=join("_",$title,$user);
            $send=SendInvition($subject,$email,$content);
            
            if ($send) {
                print "Fail to send the invition: $send\n";
            } else {
                print "Successfully invite $name $email referred by $user\n";
            }
            print "\n\n";
            my $error;
            my $error_p;
            $error=UserInvite($token,$name,$email,$user);
            if(@permissionC){
                foreach my $permission (@permissionC) {
                    print "You picked $permission.<br>\n";
                    $error_p=GrantTempUserPerm($token,$permission);
                }
            }
            
            if ($error) {
                print "Can't invite user because: $error\n";
            } else {
                print "Invite user $name $email as referred by $user\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

if ($action eq "give-opinion-data") {
    
    my $latitude = cookie('latitude');
    my $longitude = cookie('longitude');
    if (!UserCan($user,"give-opinion-data")) {
        print h2('You do not have the required permissions to give opinion.');
    } else {#change it back
        if (!$run) {
            
            
            print "current latitude is: $latitude \n";
            print "current longitude is: $longitude \n";
            
            print start_form(-name=>'GiveOpinion'),
            h2('Give Opinion'),
            "Opinion: ",
            popup_menu(
            -name => 'OpinionColor',
            -values => ['red','white','blue'],
            -default => 'blue',
            -labels => \%labels
            ),
            p,
            hidden(-name=>'run',-default=>['1']),
            hidden(-name=>'act',-default=>['give-opinion-data']),
            
            hidden(-name=>'latitude',-default=>[$latitude]),
            hidden(-name=>'longitude',-default=>[$longitude]),
            submit,
            end_form,
            hr;
        } else {
            my $opinion_color=param('OpinionColor');
            my $latitude=param("latitude");
            my $longitude=param("longitude");
            my $num_color;
            
            if($opinion_color eq'blue'){
                $num_color=1;
            }elsif($opinion_color eq'white'){
                $num_color=0;
            }else{
                $num_color=-1;
            }
            
            print "The latitude is: $latitude \n";
            print "The longitude is: $longitude \n";
            
            print "The opinion_color is: $opinion_color \n";
            my $error;
            $error=OpinionAdd($user,$num_color,$latitude,$longitude);
            if ($error) {
                print "Can't add opinion: $error";
            } else {
                print "Successfully Added opinion by $user\n";
            }
        }
    }#change it back
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

if ($action eq "give-cs-ind-data") {
    print h2("Giving Crowd-sourced Individual Geolocations Is Unimplemented");
}

#
# ACTIVATE-USER
#
# User ACTIVATE functionaltiy
#
#
#
#
if ($action eq "activate-user") {
    
    my $check = param("token");
    
    if (!CheckLink($check)) {
        print h2('The activationg link is expired');
    } else {
        my $referer=CheckLink($check);
        my @permissions = ExecSQL($dbuser, $dbpasswd, "select invite_action from rwb_permissions_temp where invite_token='$check' order by invite_action",undef);
        
        if (!$run) {
            print start_form(-name=>'ActivateUser'),
            h2('Activate your account'),
            "Name: ", textfield(-name=>'name'),
            p,
            "Email: ", textfield(-name=>'email'),
            p,
            "Password: ", textfield(-name=>'password'),
            p;
            if(@permissions){
                my $i=0;
                print
                p,
                "You will have the following permissions: \n";
                for $i ( 0 .. $#permissions ){
                    print "$permissions[$i][0].<br>\n";
                }
            }
            print
            p,
            hidden(-name=>'run',-default=>['1']),
            hidden(-name=>'act',-default=>['activate-user']),
            hidden(-name=>'by',-default=>[$referer]),
            hidden(-name=>'token',-default=>[$check]),
            hidden(-name=>'permissionC',-default=>[@permissions]),          
            submit,
            end_form,
            hr;
        } else {
            my $name=param('name');
            my $email=param('email');
            my $password=param('password');
            my $by=param('by');
            my $check=param('token');
            my @permissionC=param('permissionC');      
            my $error;
            my $error_ap;      
            my $del_pending_user;
            my $del_pending_perm;      
            my $salt = 'ab';
            my $cryptedpwd = crypt $password, $salt;             
            $error=UserAdd($name,$cryptedpwd,$email,$by);
            if(@permissionC){
                my $i=0;      
                for $i ( 0 .. $#permissions ){
                    $error_ap=GiveUserPerm($name,$permissions[$i][0]);  
                }      
            }
            if ($error) { 
                print "Can't activate your account: $error";
            } else {
                if($#permissionC>0){        
                    $del_pending_perm=PendingPermDel($check);  
                }      
                $del_pending_user=PendingUserDel($check);
                
                if(!$del_pending_perm||!$del_pending_user) { 
                    print "Successfully added user $name $email as referred by $by\n";
                }
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}
#Edit by XiaofengZhu
if ($action eq "give-cs-ind-data") {
    print h2("Giving Crowd-sourced Individual Geolocations Is Unimplemented");
}
#
# ADD-USER
#
# User Add functionaltiy 
#
#
#
#
if ($action eq "add-user") { 
    if (!UserCan($user,"add-users") && !UserCan($user,"manage-users")) { 
        print h2('You do not have the required permissions to add users.');
    } else {
        if (!$run) { 
            print start_form(-name=>'AddUser'),
                  h2('Add User'),
                  "Name: ", textfield(-name=>'name'),
                  p,
                  "Email: ", textfield(-name=>'email'),
                  p,
                  "Password: ", textfield(-name=>'password'),
                  p,
                  hidden(-name=>'run',-default=>['1']),
                  hidden(-name=>'act',-default=>['add-user']),
                  submit,
                  end_form,
                  hr;
        } else {
            my $name=param('name');
            my $email=param('email');
            my $password=param('password');
            my $salt = 'ab';
            my $cryptedpwd = crypt $password, $salt;            
            my $error;
            $error=UserAdd($name,$cryptedpwd,$email,$user);
            if ($error) { 
                print "Can't add user because: $error";
            } else {
                print "Added user $name $email as referred by $user\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

#
# DELETE-USER
# User Delete functionaltiy 
#
#
#
#
if ($action eq "delete-user") { 
    if (!UserCan($user,"manage-users")) { 
        print h2('You do not have the required permissions to delete users.');
    } else {
        if (!$run) { 
#
# Generate the add form.
#
            print start_form(-name=>'DeleteUser'),
                  h2('Delete User'),
                  "Name: ", textfield(-name=>'name'),
                  p,
                  hidden(-name=>'run',-default=>['1']),
                  hidden(-name=>'act',-default=>['delete-user']),
                  submit,
                  end_form,
                  hr;
        } else {
            my $name=param('name');
            my $error;
            $error=UserDelete($name);
            if ($error) { 
                print "Can't delete user because: $error";
            } else {
                print "Deleted user $name\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}


#
# ADD-PERM-USER
#
# User Add Permission functionaltiy 
#
#
#
#
if ($action eq "add-perm-user") { 
    if (!UserCan($user,"manage-users")) { 
        print h2('You do not have the required permissions to manage user permissions.');
    } else {
        if (!$run) { 
#
# Generate the add form.
#
            print start_form(-name=>'AddUserPerm'),
                  h2('Add User Permission'),
                  "Name: ", textfield(-name=>'name'),
                  "Permission: ", textfield(-name=>'permission'),
                  p,
                  hidden(-name=>'run',-default=>['1']),
                  hidden(-name=>'act',-default=>['add-perm-user']),
                  submit,
                  end_form,
                  hr;
            my ($table,$error);
            ($table,$error)=PermTable();
            if (!$error) { 
                print "<h2>Available Permissions</h2>$table";
            }
        } else {
            my $name=param('name');
            my $perm=param('permission');
            my $error=GiveUserPerm($name,$perm);
            if ($error) { 
                print "Can't add permission to user because: $error";
            } else {
                print "Gave user $name permission $perm\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}


#
# REVOKE-PERM-USER
#
# User Permission Revocation functionaltiy 
#
#
#
#
if ($action eq "revoke-perm-user") { 
    if (!UserCan($user,"manage-users")) { 
        print h2('You do not have the required permissions to manage user permissions.');
    } else {
        if (!$run) { 
#
# Generate the add form.
#
            print start_form(-name=>'RevokeUserPerm'),
                  h2('Revoke User Permission'),
                  "Name: ", textfield(-name=>'name'),
                  "Permission: ", textfield(-name=>'permission'),
                  p,
                  hidden(-name=>'run',-default=>['1']),
                  hidden(-name=>'act',-default=>['revoke-perm-user']),
                  submit,
                  end_form,
                  hr;
            my ($table,$error);
            ($table,$error)=PermTable();
            if (!$error) { 
                print "<h2>Available Permissions</h2>$table";
            }
        } else {
            my $name=param('name');
            my $perm=param('permission');
            my $error=RevokeUserPerm($name,$perm);
            if ($error) { 
                print "Can't revoke permission from user because: $error";
            } else {
                print "Revoked user $name permission $perm\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}



# Debugging output is the last thing we show, if it is set
#
print "</center>" if !$debug;

#
# Generate debugging output if anything is enabled.
#
#
if ($debug) {
    print hr, p, hr,p, h2('Debugging Output');
    print h3('Parameters');
    print "<menu>";
    print map { "<li>$_ => ".escapeHTML(param($_)) } param();
    print "</menu>";
    print h3('Cookies');
    print "<menu>";
    print map { "<li>$_ => ".escapeHTML(cookie($_))} cookie();
    print "</menu>";
    my $max= $#sqlinput>$#sqloutput ? $#sqlinput : $#sqloutput;
    print h3('SQL');
    print "<menu>";
    for (my $i=0;$i<=$max;$i++) { 
        print "<li><b>Input:</b> ".escapeHTML($sqlinput[$i]);
        print "<li><b>Output:</b> $sqloutput[$i]";
    }
    print "</menu>";
}

#Todo: remove the div
print "<div>"; 

#
# The main line is finished at this point. 
# The remainder includes utilty and other functions
#
#
# Generate a table of nearby committees
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Committees {
    my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
    my @rows;
    eval { 
        @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, cmte_nm, cmte_pty_affiliation, cmte_st1, cmte_st2, cmte_city, cmte_st, cmte_zip from cs339.committee_master natural join cs339.cmte_id_to_geo where cycle in (".$cycle.") and latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
    };
    if ($@) { 
        return (undef,$@);
    } else {
        if ($format eq "table") { 
            return (MakeTable("committee_data","2D",
                        ["latitude", "longitude", "name", "party", "street1", "street2", "city", "state", "zip"],
                        @rows),$@);
        } else {
            return (MakeRaw("committee_data","2D",@rows),$@);
        }
    }
}

sub ec3{
    my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
     my @rows;
     my $counter=1;
     my @rows2;
     do{
     @rows= ExecSQL($dbuser, $dbpasswd, "select count(*) from election_result_rwb where latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
     
        $latsw = $latsw - 1;
        $latne = $latne + 1;
        $longsw = $longsw - 1;
        $longne = $longne + 1;
        if($counter++==100) {
        goto EC3NEXT;
        }
} while($rows[0][0]==0);
EC3NEXT: 
     @rows2= ExecSQL($dbuser, $dbpasswd, "select year, pty, name, votes from election_result_rwb where latitude>? and latitude<? and longitude>? and longitude<? order by votes desc",undef,$latsw,$latne,$longsw,$longne);
    return MakeTable("ec3_data", "2D",["year","party", "name","votes in desc order"],@rows2);
}

#aggregated view for committes. 
#this function will search for larger areas if theres not enough information. 
sub aggCommittees{
    my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
    my @rowsDem;
    my @rowsRep;
    my $sum=0;
    my $counter=1;
#this while loop will continue running until there is enough data to compare each parties' money distribution to certain area. 
    do{
        print "$counter times in aggCommittees` loop"."<br>";
        @rowsDem= ExecSQL($dbuser, $dbpasswd, "select sum(transaction_amnt) from cs339.committee_master natural join cs339.cmte_id_to_geo natural join cs339.comm_to_comm where cycle in (".$cycle.") and latitude>? and latitude<? and longitude>? and longitude<? and cmte_pty_affiliation='DEM'",undef,$latsw,$latne,$longsw,$longne);
        @rowsRep= ExecSQL($dbuser, $dbpasswd, "select sum(transaction_amnt) from cs339.committee_master natural join cs339.cmte_id_to_geo natural join cs339.comm_to_comm where cycle in (".$cycle.") and latitude>? and latitude<? and longitude>? and longitude<? and cmte_pty_affiliation='REP'",undef,$latsw,$latne,$longsw,$longne);
        print "rowsDem returns: ".$rowsDem[0][0]."";
        print "rowsRep returns:".$rowsRep[0][0]."<br>";
        $latsw = $latsw - 0.01;
        $latne = $latne + 0.01;
        $longsw = $longsw - 0.01;
        $longne = $longne + 0.01;
        if($counter++ == 100){
            goto COMMITTEESNEXT;
        }
    } while ($rowsRep[0][0]==$rowsDem[0][0]);
COMMITTEESNEXT:
    CreateAggTable( $rowsRep[0][0], $rowsDem[0][0],"committee");
}

#
# Generate a table of nearby candidates
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
#


sub aggCandidates {
    my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
    my @rowsRep;
    my @rowsDem;
    my $sum;
    my $counter=1;
    do{
        print "$counter times in aggCandidate Loop<br>";
        @rowsRep = ExecSQL($dbuser, $dbpasswd, "select sum(transaction_amnt) from cs339.candidate_master natural join cs339.cand_id_to_geo natural join cs339.comm_to_cand where cycle in (".$cycle.") and latitude >".$latsw."  and latitude < ".$latne." and longitude >".$longsw."  and longitude<".$longne." and cand_pty_affiliation='REP'",undef);
        @rowsDem = ExecSQL($dbuser, $dbpasswd, "select sum(transaction_amnt) from cs339.candidate_master natural join cs339.cand_id_to_geo natural join cs339.comm_to_cand where cycle in (".$cycle.") and latitude >".$latsw."  and latitude < ".$latne." and longitude >".$longsw."  and longitude<".$longne." and cand_pty_affiliation='DEM'",undef);
        print "in candidate: REP: ".$rowsRep[0][0];
        print "in candidate: DEM: ".$rowsDem[0][0];
        $latsw = $latsw - 0.1;
        $latne = $latne + 0.1;
        $longsw = $longsw - 0.1;
        $longne = $longne + 0.1;
        if($counter++==100){
            goto CANDIDATESNEXT;   
        };
    } while ($rowsRep[0][0]==$rowsDem[0][0]);
#
CANDIDATESNEXT:
    CreateAggTable( $rowsRep[0][0], $rowsDem[0][0],"candidate");
}

#
# Generate a table of nearby Individuals
# ($table|$raw,$error) = Individuals(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
#


sub aggIndividuals {
    my ($latne, $longne, $latsw, $longsw, $cycle,$format) = @_;
    my @rows;
    print "in aggindividuals";
    my $counter = 1;
do{
    @rows = ExecSQL($dbuser, $dbpasswd, "select sum(transaction_amnt) from cs339.individual natural join cs339.ind_to_geo where cycle in (".$cycle.") and latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
        print "aggindividual: ".$rows[0][0];
        $latsw = $latsw - 0.1;
        $latne = $latne + 0.1;
        $longsw = $longsw - 0.1;
        $longne = $longne + 0.1;
if($counter++==100){
goto INDIVIDUALSNEXT;
}
}while($rows[0][0]==0);

INDIVIDUALSNEXT:
#assumes the operation is complete. 

    print MakeTable("individual_agg_data", "2D",["sum of money for individuals"],@rows);

}

sub Candidates {
    my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
    my @rows;
    eval { 
        @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, cand_name, cand_pty_affiliation, cand_st1, cand_st2, cand_city, cand_st, cand_zip from cs339.candidate_master natural join cs339.cand_id_to_geo where cycle in (".$cycle.") and latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
    };

    if ($@) { 
        return (undef,$@);
    } else {
        if ($format eq "table") {
            return (MakeTable("candidate_data", "2D",
                        ["latitude", "longitude", "name", "party", "street1", "street2", "city", "state", "zip"],
                        @rows),$@);
        } else {
            return (MakeRaw("candidate_data","2D",@rows),$@);
        }
    }
}
#
# Generate a table of nearby individuals
#
# Note that the handout version does not integrate the crowd-sourced data
#
# ($table|$raw,$error) = Individuals(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Individuals {
    my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
    my @rows;
    eval { 
        @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, name, city, state, zip_code, employer, transaction_amnt from cs339.individual natural join cs339.ind_to_geo where cycle in (".$cycle.") and latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
    };

    if ($@) { 
        return (undef,$@);
    } else {
        if ($format eq "table") { 
            return (MakeTable("individual_data", "2D",
                        ["latitude", "longitude", "name", "city", "state", "zip", "employer", "amount"],
                        @rows),$@);
        } else {
            return (MakeRaw("individual_data","2D",@rows),$@);
        }
    }
}


#
# Generate a table of nearby opinions
#
# ($table|$raw,$error) = Opinions(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Opinions {
    my ($latne, $longne, $latsw, $longsw, $cycle,$format) = @_;
    my @rows;
    eval { 
        @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, color from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
    };

    if ($@) { 
        return(undef,$@);
    } else {
        if ($format eq "table") { 
            return (MakeTable("opinion_data","2D",
                        ["latitude", "longitude", "name", "city", "state", "zip", "employer", "amount"],
                        @rows),$@);
        } else {
            return (MakeRaw("opinion_data","2D",@rows),$@);
        }
    }
}


sub aggOpinions {
    my ($latne, $longne, $latsw, $longsw, $cycle,$format) = @_;
    my @rows;
    print "in aggOpinions";
    my $counter = 1;
do{
    @rows = ExecSQL($dbuser, $dbpasswd, "select stddev(color), avg(color) from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
    print "stddev: ".$rows[0][0]."avg: ".$rows[0][1]."<br>";
        $latsw = $latsw - 0.1;
        $latne = $latne + 0.1;
        $longsw = $longsw - 0.1;
        $longne = $longne + 0.1;
if($counter++==100){
goto OPINIONSNEXT;
}
}while($rows[0][1]==0.5||($rows[0][0]==0&&$rows[0][1]==0));

OPINIONSNEXT:
#assumes the operation is complete. 
CreateAggTable($rows[0][1],$rows[0][0],"opinions");
#Todo: include the average and standard deviation of colors, and then color the map to blue if average is <0.5, else to red.  
}

# Todo: change place of this tag.
#
print "</div>";
print end_html;
sub average{
    my($data) = @_;
    if (not @$data) {
        die("Empty array\n");
    }
    my $total = 0;
    foreach (@$data) {
        $total += $_;
    }
    my $average = $total / @$data;
    return $average;
}
sub stdev{
    my($data) = @_;
    if(@$data == 1){
        return 0;
    }
    my $average = &average($data);
    my $sqtotal = 0;
    foreach(@$data) {
        $sqtotal += ($average-$_) ** 2;
    }
    my $std = ($sqtotal / (@$data-1)) ** 0.5;
    return $std;
}


#generate a table for aggregate views. 
sub CreateAggTable{
    my($rep, $dem, $name) = @_;
    my $sum = $rep + $dem;
    my $color = "blue";
    if($name ne "opinions"){
    if($rep>$dem){
        $color = "red";
    }
    print "creating table";
    print "<div id = \"$name\">";
    print "<table style=\"background-color:$color;\">";
    print"<tr>";
    print "<th>".$name . " Summary Sum of money</th>";
    print "<th> Rep </th>";
    print "<th> Dem </th>";
    print "</tr>";
    print "<tr>";
    print "<td>".$sum."</td>";
    print "<td>".$rep."</td>";
    print "<td>".$dem."</td>";
    print "</tr>";
    print "</table>";
    print "</div>"; 
    }
    else{
    my $avg = $rep;
    my $std = $dem;
    if($avg>0.5){
        $color = "red";
    }
    print "creating table";
    print "<div id = \"$name\">";
    print "<table style=\"background-color:$color;\">";
    print"<tr>";
    print "<th>".$name . " Summary</th>";
    print "<th> Average </th>";
    print "<th> Standard Deviation </th>";
    print "</tr>";
    print "<tr>";
    print "<td></td>";
    print "<td>".$avg."</td>";
    print "<td>".$std."</td>";
    print "</tr>";
    print "</table>";
    print "</div>"; 

    }
}
#
# Generate a table of available permissions
# ($table,$error) = PermTable()
# $error false on success, error string on failure
#
sub PermTable {
    my @rows;
    eval { @rows = ExecSQL($dbuser, $dbpasswd, "select action from rwb_actions"); }; 
    if ($@) { 
        return (undef,$@);
    } else {
        return (MakeTable("perm_table",
                    "2D",
                    ["Perm"],
                    @rows),$@);
    }
}

#
# Generate a table of users
# ($table,$error) = UserTable()
# $error false on success, error string on failure
#
sub UserTable {
    my @rows;
    eval { @rows = ExecSQL($dbuser, $dbpasswd, "select name, email from rwb_users order by name"); }; 
    if ($@) { 
        return (undef,$@);
    } else {
        return (MakeTable("user_table",
                    "2D",
                    ["Name", "Email"],
                    @rows),$@);
    }
}

#
# Generate a table of users and their permissions
# ($table,$error) = UserPermTable()
# $error false on success, error string on failure
#
sub UserPermTable {
    my @rows;
    eval { @rows = ExecSQL($dbuser, $dbpasswd, "select rwb_users.name, rwb_permissions.action from rwb_users, rwb_permissions where rwb_users.name=rwb_permissions.name order by rwb_users.name"); }; 
    if ($@) { 
        return (undef,$@);
    } else {
        return (MakeTable("userperm_table",
                    "2D",
                    ["Name", "Permission"],
                    @rows),$@);
    }
}
#Edit by XiaofengZhu
#
# Invite a user
# call with name,email
#
# returns false on success, error string on failure.
#
# UserAdd($name,$password,$email)
#
# sub CreateInviteTemp {
#    eval{ ExecSQL($dbuser,$dbpasswd,
#      "CREATE TABLE IF NOT EXISTS temp_invite (
#       name  varchar(64) not null primary key,
#       email varchar(256) not null UNIQUE
#       constraint email_ok CHECK (email LIKE '%@%'),
#       referer varchar(64) not null references rwb_users(name),
#       constraint referer check (referer='root' or referer<>name))",undef,@_);};
#    return $@;
#   # eval { ExecSQL($dbuser,$dbpasswd,
#   #    "insert into temp_invite (name,email,referer) values (?,?,?)",undef,@_);};
#   # return $@;
# }
sub SendInvition {
    my ($subject, $address,$content)=@_;
    
    # $subject="Your New Account";
    
    # $newcontent="Your New Account is <.....>";
    # #
    # # This is the magic.  It means "run mail -s ..." and let me
    
    # # write to its input, which I will call MAIL:
    # #
    
    open(MAIL,"| mailx -s $subject $address") or die "Can't run mail\n";
    
    # #
    
    # # And here we write to it
    
    # #
    
    print MAIL $content;
    
    # #
    
    # # And then close it, resulting in the email being sent
    # #
    
    close(MAIL);
    
    return 0;
}

sub UserInvite {
    eval { ExecSQL($dbuser,$dbpasswd,
        "insert into rwb_invite_temp (invite_token,invite_name,email,referer) values (?,?,?,?)",undef,@_);};
    return $@;
}

sub CheckLink {
    my ($invite_token)=@_;
    my @col;
    eval {@col=ExecSQL($dbuser,$dbpasswd, "select referer from rwb_invite_temp where invite_token=?","COL",$invite_token);};
    if ($@) {
        return 0;
    } else {
        return $col[0];
    }
}
#
# Delete a pending user
# returns false on success, $error string on failure
#
sub PendingUserDel {
    eval {ExecSQL($dbuser,$dbpasswd,"delete from rwb_invite_temp where invite_token=?", undef, @_);};
    return $@;
}
#
# Delete a pending perm
# returns false on success, $error string on failure
#
sub PendingPermDel {
    eval {ExecSQL($dbuser,$dbpasswd,"delete from rwb_permissions_temp where invite_token=?", undef, @_);};
    return $@;
}
#Edit by XiaofengZhu
#
# Add a user
# call with name,password,email
#
# returns false on success, error string on failure.
# 
# UserAdd($name,$password,$email)
#
#
# Add a user
# call with name,password,email
#
# returns false on success, error string on failure.
# 
# UserAdd($name,$password,$email)
#
sub UserAdd { 
    eval { ExecSQL($dbuser,$dbpasswd,
            "insert into rwb_users (name,password,email,referer) values (?,?,?,?)",undef,@_);};
    return $@;
}

#
# Delete a user
# returns false on success, $error string on failure
# 
sub UserDel { 
    eval {ExecSQL($dbuser,$dbpasswd,"delete from rwb_users where name=?", undef, @_);};
    return $@;
}


#
# Give a user a permission
#
# returns false on success, error string on failure.
# 
# GiveUserPerm($name,$perm)
#
sub GiveUserPerm { 
    eval { ExecSQL($dbuser,$dbpasswd,
            "insert into rwb_permissions (name,action) values (?,?)",undef,@_);};
    return $@;
}
#Edit by XiaofengZhu
sub OpinionAdd {
    eval { ExecSQL($dbuser,$dbpasswd,
        "insert into rwb_opinions (submitter,color,latitude,longitude) values (?,?,?,?)",undef,@_);};
    return $@;
}


# sub GetRefererPerm {
#   my @rows;
#   eval {
#     @rows = ExecSQL($dbuser, $dbpasswd, "select action from rwb_permissions where name=? order by action",undef); };

#   if ($@) {
#     return (undef,$@);
#   } else {
#       retun @rows;
#   }
# }
# sub GetTempPerm {
#   my @rows;
#   eval {
#     @rows = ExecSQL($dbuser, $dbpasswd, "select invite_action from rwb_permissions_temp where invite_token=? order by invite_action",undef,@_);};


#   if ($@) {
#     return (undef,$@);
#   } else {
#       retun @rows;
#   }
# }

#
# Grant a user permissions from rwb_permissions_temp
#
# returns false on success, error string on failure.
#
# GiveUserPerm($name,$perm)
#
sub GrantTempUserPerm {
    eval { ExecSQL($dbuser,$dbpasswd,
        "insert into rwb_permissions_temp (invite_token,invite_action) values (?,?)",undef,@_);};
    return $@;
}
#Edit by XiaofengZhu

#
# Revoke a user's permission
#
# returns false on success, error string on failure.
# 
# RevokeUserPerm($name,$perm)
#
sub RevokeUserPerm { 
    eval { ExecSQL($dbuser,$dbpasswd,
            "delete from rwb_permissions where name=? and action=?",undef,@_);};
    return $@;
}

#
#
# Check to see if user and password combination exist
#
# $ok = ValidUser($user,$password)
#
#
#

sub ValidUser {
    my ($user,$password)=@_;
    my @col;
    eval {@col=ExecSQL($dbuser,$dbpasswd, "select count(*) from rwb_users where name=? and password=?","COL",$user,$password);};
    if ($@) { 
        return 0;
    } else {
        return $col[0]>0;
    }
}


#
#
# Check to see if user can do some action
#
# $ok = UserCan($user,$action)
#
sub UserCan {
    my ($user,$action)=@_;
    my @col;
    eval {@col= ExecSQL($dbuser,$dbpasswd, "select count(*) from rwb_permissions where name=? and action=?","COL",$user,$action);};
    if ($@) { 
        return 0;
    } else {
        return $col[0]>0;
    }
}





#
# Given a list of scalars, or a list of references to lists, generates
# an html table
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
# $headerlistref points to a list of header columns
#
#
# $html = MakeTable($id, $type, $headerlistref,@list);
#
sub MakeTable {
    my ($id,$type,$headerlistref,@list)=@_;
    my $out;
#
# Check to see if there is anything to output
#
    if ((defined $headerlistref) || ($#list>=0)) {
# if there is, begin a table
#
        $out="<table id=\"$id\" border>";
#
# if there is a header list, then output it in bold
#
        if (defined $headerlistref) { 
            $out.="<tr>".join("",(map {"<td><b>$_</b></td>"} @{$headerlistref}))."</tr>";
        }
#
# If it's a single row, just output it in an obvious way
#
        if ($type eq "ROW") { 
#
# map {code} @list means "apply this code to every member of the list
# and return the modified list.  $_ is the current list member
#
            $out.="<tr>".(map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>" } @list)."</tr>";
        } elsif ($type eq "COL") { 
#
# ditto for a single column
#
            $out.=join("",map {defined($_) ? "<tr><td>$_</td></tr>" : "<tr><td>(null)</td></tr>"} @list);
        } else { 
#
# For a 2D table, it's a bit more complicated...
#
            $out.= join("",map {"<tr>$_</tr>"} (map {join("",map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>"} @{$_})} @list));
        }
        $out.="</table>";
    } else {
# if no header row or list, then just say none.
        $out.="(none)";
    }
    return $out;
}


#
# Given a list of scalars, or a list of references to lists, generates
# an HTML <pre> section, one line per row, columns are tab-deliminted
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
#
# $html = MakeRaw($id, $type, @list);
#
sub MakeRaw {
    my ($id, $type,@list)=@_;
    my $out;
#
# Check to see if there is anything to output
#
    $out="<pre id=\"$id\">\n";
#
# If it's a single row, just output it in an obvious way
#
    if ($type eq "ROW") { 
#
# map {code} @list means "apply this code to every member of the list
# and return the modified list.  $_ is the current list member
#
        $out.=join("\t",map { defined($_) ? $_ : "(null)" } @list);
        $out.="\n";
    } elsif ($type eq "COL") { 
#
# ditto for a single column
#
        $out.=join("\n",map { defined($_) ? $_ : "(null)" } @list);
        $out.="\n";
    } else {
#
# For a 2D table
#
        foreach my $r (@list) { 
            $out.= join("\t", map { defined($_) ? $_ : "(null)" } @{$r});
            $out.="\n";
        }
    }
    $out.="</pre>\n";
    return $out;
}

#
# @list=ExecSQL($user, $password, $querystring, $type, @fill);
#
# Executes a SQL statement.  If $type is "ROW", returns first row in list
# if $type is "COL" returns first column.  Otherwise, returns
# the whole result table as a list of references to row lists.
# @fill are the fillers for positional parameters in $querystring
#
# ExecSQL executes "die" on failure.
#
#
sub ExecSQL {
    my ($user, $passwd, $querystring, $type, @fill) =@_;
    if ($debug) { 
# if we are recording inputs, just push the query string and fill list onto the 
# global sqlinput list
        push @sqlinput, "$querystring (".join(",",map {"'$_'"} @fill).")";
    }
    my $dbh = DBI->connect("DBI:Oracle:",$user,$passwd);
    if (not $dbh) { 
# if the connect failed, record the reason to the sqloutput list (if set)
# and then die.
        if ($debug) { 
            push @sqloutput, "<b>ERROR: Can't connect to the database because of ".$DBI::errstr."</b>";
        }
        die "Can't connect to database because of ".$DBI::errstr;
    }
    my $sth = $dbh->prepare($querystring);
    if (not $sth) { 
#
# If prepare failed, then record reason to sqloutput and then die
#
        if ($debug) { 
            push @sqloutput, "<b>ERROR: Can't prepare '$querystring' because of ".$DBI::errstr."</b>";
        }
        my $errstr="Can't prepare $querystring because of ".$DBI::errstr;
        $dbh->disconnect();
        die $errstr;
    }
    if (not $sth->execute(@fill)) { 
#
# if exec failed, record to sqlout and die.
        if ($debug) { 
            push @sqloutput, "<b>ERROR: Can't execute '$querystring' with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr."</b>";
        }
        my $errstr="Can't execute $querystring with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr;
        $dbh->disconnect();
        die $errstr;
    }
#
# The rest assumes that the data will be forthcoming.
#
#
    my @data;
    if (defined $type and $type eq "ROW") { 
        @data=$sth->fetchrow_array();
        $sth->finish();
        if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","ROW",undef,@data);}
        $dbh->disconnect();
        return @data;
    }
    my @ret;
    while (@data=$sth->fetchrow_array()) {
        push @ret, [@data];
    }
    if (defined $type and $type eq "COL") { 
        @data = map {$_->[0]} @ret;
        $sth->finish();
        if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","COL",undef,@data);}
        $dbh->disconnect();
        return @data;
    }
    $sth->finish();
    if ($debug) {push @sqloutput, MakeTable("debug_sql_output","2D",undef,@ret);}
    $dbh->disconnect();
    return @ret;
}


######################################################################
#
# Nothing important after this
#
######################################################################

# The following is necessary so that DBD::Oracle can
# find its butt
#
BEGIN {
    unless ($ENV{BEGIN_BLOCK}) {
        use Cwd;
        $ENV{ORACLE_BASE}="/raid/oracle11g/app/oracle/product/11.2.0.1.0";
        $ENV{ORACLE_HOME}=$ENV{ORACLE_BASE}."/db_1";
        $ENV{ORACLE_SID}="CS339";
        $ENV{LD_LIBRARY_PATH}=$ENV{ORACLE_HOME}."/lib";
        $ENV{BEGIN_BLOCK} = 1;
        exec 'env',cwd().'/'.$0,@ARGV;
    }
}

