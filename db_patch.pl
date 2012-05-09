#!/usr/bin/perl
use strict;
use Data::Dumper;
my ( $old_db, $new_db ) = @ARGV;
my %new = ();
my %old = ();

open my $old_file, $old_db;
open my $new_file, $new_db;
$new{$_->{name}} = $_ for analyzeTable ( join "", <$new_file> );
$old{$_->{name}} = $_ for analyzeTable ( join "", <$old_file> );
close $old_file;
close $new_file;
print Dumper \%old;
exit(0);
##
## とりあえずガチマッチじゃなくて追加だけ対応
##
foreach my $key ( keys %new ) {
  if ( !defined $old{$key} ) {
    print &toCreateTable ( $new{$key} ) . "\n";
  }
  else {
    my %new_flds = ();
    my %old_flds = ();
    $new_flds{$_->{name}} = $_ for @{$new{$key}->{flds}};
    $old_flds{$_->{name}} = $_ for @{$old{$key}->{flds}};
    my $before = '';
    foreach my $fld ( @{$new{$key}->{flds}} ) {
      my $key2 = $fld->{name};
      if ( !$old_flds{$key2} )  {
        print &toAlterAdd ( $key, $new_flds{$key2}, $before ) . "\n";
      }
      $before = $key2;
    }
  }
}

#
# ALTER TABLEのADD文を作成する
#
sub toAlterAdd {
  my $tbl_name = shift;
  my $fld      = shift;
  my $before   = shift;

  my $sql = '';
  $sql .= "ALTER TABLE " . $tbl_name . " ADD ";
  $sql .= ' '   . $fld->{name} ;
  $sql .= ' '   . $fld->{data_type};
  $sql .= ' '   . $fld->{nullable} ? ' NULL ' : ' NOT NULL ';
  $sql .= ' '   . "AUTO_INCREMENT" if defined $fld->{auto_increment};
  if ( defined $fld->{default} ) {
    if    ( $fld->{default} =~ /NULL/i )                               { $sql .= ' '   . "DEFAULT NULL "; }
    elsif ( $fld->{data_type} =~ /int|numeric|float|double|decimal/i ) { $sql .= ' '   . "DEFAULT " . $fld->{default}; }
    else                                                               { $sql .= ' '   . "DEFAULT '" . escapeSQL ( $fld->{default} ) ."'" ; }
  }
  $sql .= ' '   . "AFTER `"   . $before . "`"                      if $before;
  return $sql . ';';
}

#
# CREATE TABLE文を作成する
#
sub toCreateTable {
  my $tbl = shift;
  my $sql = 'CREATE TABLE `' . $tbl->{name} . '` ('; 
  my @flds = ();
  foreach my $fld ( @{$tbl->{flds}} ) {
    my $str_fld = "`" . $fld->{name} .'`';
    $str_fld .= ' ' . $fld->{data_type};
    $str_fld .= ' ' . $fld->{nullable} ? ' NULL ' : ' NOT NULL ';
    $str_fld .= ' ' . "AUTO_INCREMENT" if defined $fld->{auto_increment};
    if ( defined $fld->{default} ) {
      if    ( $fld->{default} =~ /NULL/i )                               { $str_fld .= ' ' . "DEFAULT NULL "; }
      elsif ( $fld->{data_type} =~ /int|numeric|float|double|decimal/i ) { $str_fld .= ' ' . "DEFAULT " . $fld->{default}; }
      else                                                               { $str_fld .= ' ' . "DEFAULT '" . escapeSQL ( $fld->{default} ) ."'" ; }
    }
    $str_fld .= ' '   . "COMMENT '" . escapeSQL ( $fld->{comment} ) ."'" if defined $fld->{comment};
    $str_fld .= ' '   . "primary key"                                    if defined $fld->{primary_key};
    push @flds, $str_fld;
  }
  push @flds, ( 'PRIMARY KEY (' . join ( ',', @{$tbl->{primary_keys}} ) . ')' ) if defined $tbl->{primary_keys};
  $sql .= join ',', @flds;
  $sql .= ')';
  $sql .= " ENGINE=InnoDB DEFAULT CHARSET=utf8 ";
  $sql .= " COMMENT='" . escapeSQL ( $tbl->{comment} )  if defined $tbl->{comment};
  return $sql . ";";
}

#
# SQL文のescape
#
sub escapeSQL {
  $_[0] =~ s/'/''/g;
  return $_[0];
}

#
# CREATE TABLE文からテーブル構造を作成する
#
sub analyzeTable {
  my $sql = shift;
  my $buf = '';
  my @result = ();
  $sql .= ' ';
  for ( my $i = 0; $i < length ( $sql ); $i++ ) {
    my $char = substr ( $sql, $i, 1 );
    if ( $char eq '-' and $buf eq '-') {
      for ( $i +=1; $i < length ( $sql ); $i++ ) {
        substr ( $sql, $i, 1 ) =~ /\n/ and last;
      }
    }
    if ( $char =~ /\S/) {
      $buf .= $char;
    }
    else {
      length $buf or next;
      if ( $buf =~ /create/i ) {
        my $buf2 = '';
        for ( $i += 1; $i < length $sql; $i++ ) {
          my $char = substr ( $sql, $i, 1 );
          if ( $char =~ /\s/  ){
            length $buf2 or next;
            last;
          }
          $buf2 .= $char;
        }  
        if ( $buf2 =~ /table/i ) {
          my $buf2 = '';
          for ( $i += 1; $i < length $sql; $i++ ) {
            my $char = substr ( $sql, $i, 1 );
            $char =~ /\s/ and next;
            $char eq '('  and last;
            if ( $buf2 =~ /^IF|NOT|EXISTS$/  ) {
              $buf2 = '';
            }
            $buf2 .= $char;
          }
          $buf2 =~ s/\`//g;
          my ( $flds, $index ) = analyzeFields ( $sql, $i + 1 );
          push @result, {
            name => $buf2,
            flds => $flds->{flds},
            primary_keys => $flds->{primary_keys},
          };
          $i = $index;
        }
        ## index とか
        elsif ( $buf2 =~ /index/i ) {
        }
        else {
          ## 他なんかあったっけ?
        }
      }
      ## TODO: ちゃんと実装する
      elsif ( $buf =~ /engine/i )  { }
      elsif ( $buf =~ /default/i ) { }
      elsif ( $buf =~ /comment/i ) { }
      $buf = '';
    }
  }
  return @result;
}

#
# CREATE TABLE文からフィールドリストを抜き出す
#
sub analyzeFields {
  my ( $sql, $index ) = @_;
  my $i = $index;
  my %result = ();
  my @flds   = ();
  my $buf    = '';
  my $fld    = {};

  for ( ; $i < length $sql; $i++ ) {
    my $char = substr ( $sql, $i, 1 );
    if ( $char eq "`" or $char eq "'" ) {  
      my $terminator = $char;
      for ( $i += 1; $i < length $sql; $i++ ) {
        my $char = substr ( $sql, $i, 1 );
        $char eq '\\'        and next;
        $char eq $terminator and last;
        $buf .= $char;
      }
    }
    elsif ( $char eq '(' ) {  
      $buf .= '(';
      for ( $i+= 1; $i < length $sql; $i++ ) {
        my $char = substr ( $sql, $i, 1 );
        $char eq ')' and last;
        $buf .= $char;
      }
      $buf .= ')';
    }
    elsif ( $char eq ')' ) {
      last;
    }
    ## 判定のタイミングとか、ここがバグの原因
=pod
    elsif ( $char eq ',' ) {
      push @flds, $fld if  $fld->{name};
      $fld = {};
    }
=cut
    elsif ( $char =~ /\s|,/ ) {
      length $buf or next;
      my $org_char = $char;
      if ( $buf =~ /primary|key|unique/i ) {
        my $buf2 = '';
        my $name = 'keys';
        if ( $buf =~ /primary/i ) {
          for ( $i += 1; $i < length $sql; $i++ ) {
            my $char = substr ( $sql, $i, 1 );
            length $buf2 or $char =~ /\s/ and next;
            $buf2 .= $char;
            $buf2 =~ /key/i and last;
          }
          $name = 'primary_keys';
        }

        ## TODO: ちゃんと実装する
        elsif ( $buf =~ /unique/i ) {
          for ( $i += 1; $i < length $sql; $i++ ) {
            my $char = substr ( $sql, $i, 1 );
            length $buf2 or $char =~ /\s/ and next;
            $buf2 .= $char;
            $buf2 =~ /key/i and last;
          }
          $name = 'unique_keys';
        }

        ## TODO: ちゃんと実装する
        else {
        }

        if ( $fld->{name} ) {
          $result{$name} = [$fld->{name}];
        }
        else {
          my $buf2 = '';
          $result{$name} = [];
          for ( $i += 1; $i < length $sql; $i++ ) {
            substr ( $sql, $i, 1 ) eq '(' and last;
          }
          for ( $i+=1 ; $i < length ( $sql ); $i++ ) {
            my $char = substr ( $sql, $i, 1 );
            length $buf2 or $char =~ /\s/ and next;
            if ( $char eq ')' or $char eq ',' ) {
              ## TODO: ちゃんと除去しましょう
              $buf2 =~ s/\`//g;
              push @{$result{$name}}, $buf2; 
              $buf2 = '';
              $char eq ')' and last;
            }
            else {
              $buf2 .= $char;
            }
          }
        }
      }
      elsif ( !$fld->{name} )             { $fld->{name}      = $buf; }
      elsif ( !$fld->{data_type} )        { $fld->{data_type} = $buf; }
      elsif ( $buf =~ /auto_increment/i ) { $fld->{auto_increment} = 1; }
      elsif ( $buf =~ /null/i )           { $fld->{nullable} = 1;     }
      elsif ( $buf =~ /not/i ) {
        $fld->{nullable} = 0;
        my $buf2 = '';
        for ( $i += 1; $i < length $sql;  $i++ ) {
          my $char = substr ( $sql, $i, 1 );
          length $buf2 or $char =~ /\s/ and next;
          $buf2 .= $char;
          $buf2 =~ /null/i and last;
        }
      }
      elsif ( $buf =~ /default/i || $buf =~ /comment/i ) {
        my $buf2       = '';
        my $terminator = '';
        for ( $i += 1; $i < length $sql; $i++ ) {
          my $char = substr ( $sql, $i, 1 );
          if ( $terminator ) {
            $char eq '\\'        and next;
            $char eq $terminator and last;
            $buf2 .= $char;
          }
          elsif ( $char =~ /\s/ || $char eq ',' ) {
            length $buf2 or next;
            $char eq ',' and $i--;
            last;
          }
          elsif ( !$terminator && ( $char eq "'"  || $char eq '`' ) ) {
            $terminator = $char;
          }
          else {
            $buf2 .= $char;
          }
        }
        $buf =~ tr/A-Z/a-z/;
        $fld->{$buf} = $buf2;
      }
      else {
        ## 何の場合?
      }
      if ( $org_char eq ',' ) {
        push @flds, $fld if  $fld->{name};
        $fld = {};
      }
      $buf = '';  
    }
    else {
      $buf .= $char;
    }
  }
  $result{flds} = \@flds;
  return \%result, $i;
}
1;

