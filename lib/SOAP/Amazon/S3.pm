package SOAP::Amazon::S3;

use warnings;
use strict;
use Time::Piece;
use Digest::HMAC_SHA1;
use MIME::Base64 qw(encode_base64 decode_base64);
use XML::MyXML 0.052 qw(tidy_xml simple_to_xml xml_to_object);
use SOAP::MySOAP 0.023;
use Carp;
use Data::Dumper;

=head1 NAME

SOAP::Amazon::S3 - A module for interfacing with Amazon S3 through SOAP

=head1 VERSION

Version 0.022

=cut

our $VERSION = '0.022';

=head1 SYNOPSIS

An object-oriented interface to handle your Amazon S3 storage. (Still experimental, although functional)

    use SOAP::Amazon::S3;

    my $s3 = SOAP::Amazon::S3->new( $access_key_id, $secret_access_key, { Debug => 1, RaiseError => 1 } );

    my @buckets = $s3->listbuckets;
    my $bucket = $s3->createbucket('mybucketname');
    my $bucket = $s3->bucket('myoldbucket'); # won't create a new bucket

    print $bucket->name;
    $bucket->delete;

    my @objects = $bucket->list;
    my $object = $bucket->putobject( $obj_key, $obj_data, { 'Content-Type' => 'text/plain' } );
    my $object = $bucket->object( $old_obj_key ); # won't put a new object in the bucket

    print $object->name;
    $object->delete;
    $object->acl('public');
    $object->acl('private');
    print $object->acl(); # will print 'public' or 'private'

    $data = $object->getdata;

=head1 FUNCTIONS

=head2 SOAP::Amazon::S3->new( $access_key_id, $secret_key_id, { Debug => 0_or_1, RaiseError => 0_or_1 } );

Creates a new S3 requester object. The {} parameters are optional and default to 0. Debug will output all SOAP communications on screen. RaiseError will make your program die if it receives an error reply from Amazon S3, and output the error message on screen. If RaiseError is off, then $s3->{'error'} will still be set to true when an S3 error occurs.

=cut

sub new {
	my $class = shift;
	my $access_key_id = shift;
	my $secret_access_key = shift;
	my $params = shift || {};

	my $self =	{
					access_key_id => $access_key_id,
					secret_access_key => $secret_access_key,
					soaper => SOAP::MySOAP->new('https://s3.amazonaws.com/soap'),
					%$params,
				};

	$self->{'soaper'}->{'ua'}->default_header( Accept => 'text/xml' );

	bless $self, $class;
}


sub _send {
	my $self = shift;
	my $command = shift;

	my @params = @_;
	
	my $t = gmtime;
	my $timestamp = $t->datetime.".000Z";
	my $canonical = "AmazonS3$command$timestamp";

	my $hmac = Digest::HMAC_SHA1->new($self->{'secret_access_key'});
	$hmac->add($canonical);
	my $signature = encode_base64($hmac->digest, '');

	push @params, ( 'AWSAccessKeyId' => $self->{'access_key_id'} );
	push @params, ( 'Timestamp' => $timestamp );
	push @params, ( 'Signature' => $signature );

	my $xml_body = simple_to_xml(\@params);



	my $xml = <<EOB;
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope 
	xmlns:wsdlsoap="http://schemas.xmlsoap.org/wsdl/soap/" 
	soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" 
	xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" 
	xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" 
	xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/" 
	xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
	xmlns:tns="http://s3.amazonaws.com/doc/2006-03-01/" 
	xmlns:xsd="http://www.w3.org/2001/XMLSchema">
	<soap:Body>
		<tns:$command xsi:nil="true">
EOB
	$xml .= $xml_body."\n";
	$xml .= <<EOB;
		</tns:$command>
	</soap:Body>
</soap:Envelope>
EOB

	$xml = tidy_xml($xml);

	my $result = $self->{'soaper'}->request($xml);
	if ($self->{'Debug'}) {
		print $self->{'soaper'}->{'request'}->as_string;
		print "\n\n\n";
		print $self->{'soaper'}->{'response'}->headers->as_string;
		print "\n";
		print &XML::MyXML::tidy_xml($self->{'soaper'}->{'response'}->content);
		print "\n";
	}

	my $obj = &xml_to_object($self->{'soaper'}{'response'}->content);
	$self->{'error'} = $obj->path("Body/Fault");
	if ($self->{'RaiseError'} and $self->{'error'}) {
		print "\nAmazon returned Fault:\n";
		print Dumper($self->{'error'}->simplify);
		confess;
	}

	return $self->{'soaper'}->{'response'}->content;
}

=head1 OBJECT METHODS

=head2 $s3->listbuckets

Returns the list of buckets in SOAP::Amazon::S3::Bucket form

=cut

sub listbuckets {
	my $self = shift;
	my $xml = $self->ListAllMyBuckets;
	my $obj = &xml_to_object($xml);
	my @buckets = map {$_->simplify} $obj->path("Body/ListAllMyBucketsResponse/ListAllMyBucketsResponse/Buckets/Bucket");
	foreach my $bucket (@buckets) {
		$bucket->{'_s3'} = $self;
		$bucket->{'Name'} = $bucket->{'Bucket'}{'Name'};
		bless $bucket, 'SOAP::Amazon::S3::Bucket';
	}
	return @buckets;
}

=head2 $s3->createbucket( $bucket_name )

Creates a bucket named $bucket_name in your S3 space and returns the appropriate ...::S3::Bucket type object for further use

=cut

sub createbucket {
	my $self = shift;
	my $name = shift;
	
	my $xml = $self->CreateBucket( Bucket => $name );
	bless { _s3 => $self, Name => $name }, 'SOAP::Amazon::S3::Bucket' unless $self->{'error'};
}

=head2 $s3->bucket( $bucket_name )

Returns an ...::S3::Bucket type object, corresponding to an already existing bucket in your S3 space, named $bucket_name

=cut 

sub bucket {
	my $self = shift;
	my $name = shift;
	
	bless { _s3 => $self, Name => $name }, 'SOAP::Amazon::S3::Bucket';
}

our $AUTOLOAD;

sub AUTOLOAD {
	my $self = shift;
	my @params = @_;
	my $command = $AUTOLOAD;
	$command =~ s/^.*\:\://;

	return $self->_send($command, @_);
}

sub DESTROY {
}




package SOAP::Amazon::S3::Bucket;

=head2 $bucket->delete

Deletes the bucket if empty. If not empty, Amazon S3 returns an error (viewable in $s3->{'error'})

=cut

sub delete {
	my $self = shift;

	$self->{'_s3'}->DeleteBucket( Bucket => $self->{'Name'} );
}

=head2 $bucket->list

Returns the list of objects in the bucket, in the form of ..::S3::Object type objects

=cut

sub list {
	my $self = shift;

	my $s3 = $self->{'_s3'};
	my $xml = $s3->ListBucket(Bucket => $self->{'Name'});
	my $obj = &XML::MyXML::xml_to_object($xml);
	my @objects = map {values %{$_->simplify}} $obj->path('Body/ListBucketResponse/ListBucketResponse/Contents');
	foreach my $object (@objects) {
		$object->{'_s3'} = $s3;
		$object->{'Bucket'} = $self->{'Name'};
		$object->{'_bucket'} = $self;
		bless $object, 'SOAP::Amazon::S3::Object';
	}

	return @objects;
}

=head2 $bucket->name

Returns the name of the bucket

=cut

sub name {
	my $self = shift;
	return $self->{'Name'};
}

=head2 $bucket->putobject( $obj_key, $obj_data, { 'Content-Type' => $mime_type } )

Creates an object in the S3 bucket, named $obj_key. The {} section is optional, and may contain the Content-Type (defaults to 'text/plain'). Returns an ...::S3::Object type object pointing to the object just created, if successful.

=cut

sub putobject {
	my $self = shift;
	my $key = shift;
	my $data = shift;
	my $options = shift || {};

	my $mimetype = $options->{'Content-Type'} || 'text/plain';

	my $s3 = $self->{'_s3'};
	$s3->PutObjectInline( Bucket => $self->name, Key => $key, Metadata => [ Name => 'Content-Type', Value => $mimetype ], Data => MIME::Base64::encode_base64($data), ContentLength => length($data) );
	bless { _s3 => $s3, Bucket => $self->name, _bucket => $self, Key => $key }, 'SOAP::Amazon::S3::Object' unless $s3->{'error'};
}

=head2 $bucket->object( $old_obj_key )

Returns an ...::S3::Object type object, corresponding to an already created object in the S3 bucket, named $old_obj_key

=cut

sub object {
	my $self = shift;
	my $key = shift;

	my $s3 = $self->{'_s3'};
	bless { _s3 => $s3, Bucket => $self->name, _bucket => $self, Key => $key }, 'SOAP::Amazon::S3::Object';
}

package SOAP::Amazon::S3::Object;

=head2 $object->name

Returns the Key attribute of an object

=cut

sub name {
	my $self = shift;
	
	return $self->{'Key'};
}

=head2 $object->delete

Deletes the object

=cut

sub delete {
	my $self = shift;
	
	my $s3 = $self->{'_s3'};
	my $bucket = $self->{'_bucket'};
	$s3->DeleteObject( Bucket => $bucket->name, Key => $self->name );
}

=head2 $object->acl( 'public' or 'private' or nothing )

Gets or sets the object's ACL, making it public (and viewable through the web) or private just to you. If no parameter is entered, returns either 'public' or 'private'.

=cut

sub acl {
	my $self = shift;
	my $what = shift;

	my $s3 = $self->{'_s3'};
	my $bucket = $self->{'_bucket'};

	if ($what) {
		if (lc($what) eq 'public') {
			$s3->SetObjectAccessControlPolicy( Bucket => $bucket->name, Key => $self->name, AccessControlList => [ Grant => [ 'Grantee xsi:type="Group"' => [ URI => 'http://acs.amazonaws.com/groups/global/AllUsers' ], Permission => 'READ' ] ] );
		} elsif (lc($what) eq 'private') {
			$s3->SetObjectAccessControlPolicy( Bucket => $bucket->name, Key => $self->name, AccessControlList => [ ] );
		} else {
			Carp::confess "Invalid policy: '$what' - valid policies are 'public' and 'private'";
		}
	} else {
		my $resp = $s3->GetObjectAccessControlPolicy( Bucket => $bucket->name, Key => $self->name );
		my $xml = &XML::MyXML::xml_to_object($resp);
		my @grants = $xml->path('Body/GetObjectAccessControlPolicyResponse/GetObjectAccessControlPolicyResponse/AccessControlList/Grant');
		foreach my $grant (@grants) {
			my $uri = $grant->path('Grantee/URI');
			if ($uri and $uri->value eq 'http://acs.amazonaws.com/groups/global/AllUsers') { return 'public'; }
		}
		return 'private';
	}
}

=head2 $object->getdata

Returns the data of the object, after fetching it from S3

=cut

sub getdata {
	my $self = shift;

	my $s3 = $self->{'_s3'};
	my $bucket = $self->{'_bucket'};

	my $resp = $s3->GetObject( Bucket => $bucket->name, Key => $self->name, GetMetadata => 'false', GetData => 'true', InlineData => 'true' );
	return if $s3->{'error'};
	my $obj = &XML::MyXML::xml_to_object($resp);
	my $data = $obj->path('Body/GetObjectResponse/GetObjectResponse/Data');
	if ($data) { $data = $data->value; } else { return; }
	return MIME::Base64::decode_base64($data);
}


=head1 AUTHOR

Alexander Karelas, C<< <karjala at karjala.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-soap-amazon-s3 at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SOAP-Amazon-S3>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc SOAP::Amazon::S3

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/SOAP-Amazon-S3>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/SOAP-Amazon-S3>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SOAP-Amazon-S3>

=item * Search CPAN

L<http://search.cpan.org/dist/SOAP-Amazon-S3>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Alexander Karelas, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of SOAP::Amazon::S3

