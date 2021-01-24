# Copied from /home/ben/projects/translations/lib/ReadTranslations.pm


package ReadTranslations;
use warnings;
use strict;
use utf8;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/
		       read_translations
		       get_lang_trans
		       write_translations
		       read_translations_table
		       write_translations_table
		       add_translations_table 
		       get_single_trans
		       get_lang_name
		       trans_to_json_file
		       %lang2name
		   /;

our %EXPORT_TAGS = (
    'all' => \@EXPORT_OK,
);
use XML::Parser;
use Carp;
use Table::Readable qw/read_table/;
#use JSON;
use JSON::Create 'create_json';

our $VERSION='0.001';

# Return a string giving the current location of the parser in the
# translation file.

sub location
{
    my ($data_ref) = @_;
    return "$data_ref->{file_name}:".$data_ref->{xml_parser}->current_line().": ";
}

sub tuv_start
{
    my ($data_ref, $attr_ref) = @_;
    my $lang = $attr_ref->{lang};
    die location ($data_ref)."No language" unless $lang;
    $data_ref->{current_lang} = $lang;
}

sub tu_start
{
    my ($data_ref, $attr_ref) = @_;
    die location ($data_ref)."No ID" unless $attr_ref->{id};
    $data_ref->{current_id} = $attr_ref->{id};
    push @{$data_ref->{id_order}}, $data_ref->{current_id};
}

sub tuv_end
{
    my ($data_ref) = @_;
    die "No character data" unless $data_ref->{current};
    my $characters = $data_ref->{current};
    $characters =~ s/^\s+|\s+$//g;
    my $lang = $data_ref->{current_lang};
    die location ($data_ref)."No lang" unless $lang;
    my $id = $data_ref->{current_id};
    die location ($data_ref)."No ID" unless $id;
    die "Duplicate of $id/$lang" if $data_ref->{trans}->{$id}->{$lang};
    $data_ref->{trans}->{$id}->{$lang} = $characters;
}

sub start
{
    my ($data_ref, $Expat, $Element, %attr) = @_;
    $data_ref->{current} ="";
    if ($Element eq "tuv") {
	tuv_start ($data_ref, \%attr);
    } elsif ($Element eq "tu") {
	tu_start ($data_ref, \%attr);
    }
}

sub character
{
    my ($data_ref, $Expat, $String) = @_;
    $data_ref->{current} .= $String;
}

sub end
{
    my ($data_ref, $Expat, $Element) = @_;
    if ($Element eq "tuv") {
	tuv_end ($data_ref);
    }
}

my $x_lang_re = qr/\{\{(\w+)\}\}/;

sub x_link
{
    my ($trans_ref, $order) = @_;
    # X-trans links to copy text from one bit of the translation to another.
    for my $id (@$order) {
        my $trans = $trans_ref->{$id};
        
        for my $lang (keys %$trans) {
            # Check the links go somewhere
            while ($trans->{$lang} =~ /$x_lang_re/g) {
		my $w = $1;
		my $t = $trans_ref->{$w}{all};
		if (! $t) {
		    $t = $trans_ref->{$w}{$lang};
		}
                if (! $t) {
                    die "Bad X-trans {{$w}} in $id for language id '$lang'.\n";
                }
		$trans->{$lang} =~ s/\{\{$w\}\}/$t/g;
            }
        }
    }
}



sub read_translations
{
    my ($file_name, $trans) = @_;
    if (! $file_name) {
	$file_name = "translations.xml";
    }
    if (! -f $file_name) {
        carp "Can't see file '$file_name'\n";
    }
    my %data;
    if ($trans) {
        $data{trans} = $trans;
    }
    else {
        $data{trans} = {};
    }
    $data{id_order} = [];
    my $xml_handlers = {Start => sub { start(\%data, @_)},
			End   => sub { end(\%data, @_)},
			Char  => sub { character(\%data, @_)}};
    my $xml = new XML::Parser (Handlers => $xml_handlers);
    $data{xml_parser} = $xml;
    $xml->parsefile ($file_name);
    x_link ($data{trans}, $data{id_order});
    if (wantarray) {
        return ($data{trans}, $data{id_order});
    }
    else {
        return $data{trans};
    }
}



sub read_translations_table
{
    my ($input_file) = @_;
    my @translations = read_table (@_);
    my %trans;
    my @order;
    for my $translation (@translations) {
        my $id = $translation->{id};
        if ($trans{$id}) {
            die "Duplicate translation for id '$id'.\n";
        }
        if (! $id) {
            my $has = join ", ", %$translation;
            die "Translation without an ID in '$input_file', looks like '$has'.\n";
        }
        $trans{$id} = $translation;
        push @order, $id;
        #print "$id\n";
    }
    # Trim whitespace
    for my $id (@order) {
        for my $lang (keys %{$trans{$id}}) {
            $trans{$id}{$lang} =~ s/^\s+|\s+$//g;
        }
    }
    x_link (\%trans, \@order);
    if (wantarray) {
        return (\%trans, \@order);
    }
    else {
        return \%trans;
    }

}



sub add_translations_table
{
    my ($trans, $file) = @_;
    my $trans2 = read_translations_table ($file);
    for my $id (keys %$trans2) {
	if ($trans->{$id}) {
	    warn "$id is duplicated.\n";
	}
	else {
	    $trans->{$id} = $trans2->{$id};
	}
    }
}



sub get_single_trans
{
    my ($trans, $id, $lang) = @_;
    if (! $trans->{$id}) {
        croak "Unknown id '$id'";
    }
    if (! $trans->{$id}->{$lang}) {
        carp "Id '$id' has no translation in $lang";
    }
    return $trans->{$id}->{$lang};
}



sub get_lang_trans
{
    my ($trans, $vars, $lang, $verbose) = @_;
    my $varstrans = {};
    for my $id (keys %{$trans}) {
        if ($verbose) {
            print "$id, $trans->{$id}{$lang}\n";
        }
        my $value;
	if ($trans->{$id}{all}) {
	    $value = $trans->{$id}{all};
	}
	else {
	    $value = $trans->{$id}{$lang};
	}
        # The following test checks whether $value is defined because
        # an empty string may be a valid translation (for example if
        # something does not need to be translated).
        if (! defined $value) {
            #warn "No translation for $id for language $lang: substituting English.";
            $value = $trans->{$id}->{en};
        }
        $varstrans->{$id} = $value;
    }
    $vars->{trans} = $varstrans;
}



sub write_translations
{
    my ($trans, $lang_ref, $file_name, $id_order_ref) = @_;
    if (ref $lang_ref ne 'ARRAY') {
        croak "write_translations requires an array reference of languages to print as its second argument.";
    }
    open my $output, '>:encoding(utf8)', $file_name or die $!;
    print $output <<EOF;
<tmx>
EOF
    my @id_order;
    if ($id_order_ref) {
        @id_order = @{$id_order_ref};
    }
    else {
        @id_order = keys %$trans;
    }
    for my $id (@id_order) {
        print $output <<EOF;
<tu id='$id'>
EOF
        for my $lang (@$lang_ref) {
            my $t = $trans->{$id}->{$lang};
            if (! $t) {
                $t = $trans->{$id}->{en};
            }
            if (! $t) {
                croak "Translation $id does not have an English translation.";
            }
            # The conversion of & to &amp; must come first, otherwise
            # the other entities are also affected.
            $t =~ s/&/&amp;/g;
            $t =~ s/</&lt;/g;
            $t =~ s/>/&gt;/g;
            $t =~ s/"/&quot;/g;
            print $output <<EOF;
<tuv lang='$lang'>
$t
</tuv>
EOF
        }
        print $output <<EOF;
</tu>
EOF
    }
    print $output <<EOF;
</tmx>
EOF
    close $output;
}



sub write_translations_table
{
    my ($trans, $lang_ref, $file_name, $id_order_ref) = @_;
    if (ref $lang_ref ne 'ARRAY') {
        croak "write_translations_table requires an array reference of languages to print as its second argument.";
    }
    open my $output, '>:encoding(utf8)', $file_name or die $!;
    my @id_order;
    if ($id_order_ref) {
        @id_order = @{$id_order_ref};
    }
    else {
        warn "No order supplied.\n";
        @id_order = keys %$trans;
    }
    for my $id (@id_order) {
        print $output "id: $id\n";
        for my $lang (@$lang_ref) {
            my $t = $trans->{$id}->{$lang};
            if (! $t) {
                $t = $trans->{$id}->{en};
            }
            if (! $t) {
                croak "Translation $id does not have an English translation.";
            }
            $t =~ s/\s+$//;
            print $output "%%$lang:\n$t\n%%\n";
        }
        print $output "\n";
    }
    close $output;
}

# This is the old version. See ../util/langlist for generator scripts.

# our %lang2name = (
# 'af' => 'Afrikaans' ,
# 'als' => 'Alemannisch' ,
# 'am' => 'አማርኛ' ,
# 'ang' => 'Ænglisc' ,
# 'ab' => 'Аҧсуа' ,
# 'ar' => 'العربية' ,
# 'an' => 'Aragonés' ,
# 'ast' => 'Asturianu' ,
# 'gn' => 'Avañe' ,
# 'ay' => 'Aymar aru' ,
# 'az' => 'Azrbaycanca' ,
# 'bjn' => 'Bahasa Banjar' ,
# 'bn' => 'বাংলা' ,
# 'zh-min-nan' => 'Bân-lâm-gú' ,
# 'ba' => 'Башҡортса' ,
# 'be' => 'Беларуская' ,
# 'be-x-old' => '‪Беларуская (тарашкевіца)‬' ,
# 'bo' => 'བོད་ཡིག' ,
# 'bs' => 'Bosanski' ,
# 'br' => 'Brezhoneg' ,
# 'bg' => 'Български' ,
# 'ca' => 'Català' ,
# 'cv' => 'Чӑвашла' ,
# 'ceb' => 'Cebuano' ,
# 'cs' => 'Česky' ,
# 'cy' => 'Cymraeg' ,
# 'da' => 'Dansk' ,
# 'de' => 'Deutsch' ,
# 'nv' => 'Diné bizaad' ,
# 'et' => 'Eesti' ,
# 'el' => 'Ελληνικά' ,
# 'myv' => 'Эрзянь' ,
# 'es' => 'Español' ,
# 'eo' => 'Esperanto' ,
# 'eu' => 'Euskara' ,
# 'fa' => 'فارسی' ,
# 'hif' => 'Fiji Hindi' ,
# 'fo' => 'Føroyskt' ,
# 'fr' => 'Français' ,
# 'fy' => 'Frysk' ,
# 'ga' => 'Gaeilge' ,
# 'gv' => 'Gaelg' ,
# 'gd' => 'Gàidhlig' ,
# 'gl' => 'Galego' ,
# 'hak' => 'Hak-kâ-fa' ,
# 'xal' => 'Хальмг' ,
# 'ko' => '한국어' ,
# 'ha' => 'هَوُسَ' ,
# 'hi' => 'हिन्दी' ,
# 'hsb' => 'Hornjoserbsce' ,
# 'hr' => 'Hrvatski' ,
# 'io' => 'Ido' ,
# 'bpy' => 'ইমার ঠার/বিষ্ণুপ্রিয়া মণিপুরী' ,
# 'id' => 'Bahasa Indonesia' ,
# 'iu' => 'ᐃᓄᒃᑎᑐᑦ/inuktitut' ,
# 'ik' => 'Iñupiak' ,
# 'is' => 'Íslenska' ,
# 'it' => 'Italiano' ,
# 'he' => 'עברית' ,
# 'jv' => 'Basa Jawa' ,
# 'pam' => 'Kapampangan' ,
# 'rw' => 'Kinyarwanda' ,
# 'sw' => 'Kiswahili' ,
# 'kv' => 'Коми' ,
# 'ht' => 'Kreyòl ayisyen' ,
# 'ku' => 'Kurdî' ,
# 'la' => 'Latina' ,
# 'lv' => 'Latviešu' ,
# 'lb' => 'Lëtzebuergesch' ,
# 'lt' => 'Lietuvių' ,
# 'li' => 'Limburgs' ,
# 'ln' => 'Lingála' ,
# 'jbo' => 'Lojban' ,
# 'hu' => 'Magyar' ,
# 'mk' => 'Македонски' ,
# 'mg' => 'Malagasy' ,
# 'ml' => 'മലയാളം' ,
# 'mr' => 'मराठी' ,
# 'arz' => 'مصرى' ,
# 'ms' => 'Bahasa Melayu' ,
# 'my' => 'မြန်မာဘာသာ' ,
# 'nah' => 'Nāhuatl' ,
# 'fj' => 'Na Vosa Vakaviti' ,
# 'nl' => 'Nederlands' ,
# 'nds-nl' => 'Nedersaksisch' ,
# 'cr' => 'Nēhiyawēwin / ᓀᐦᐃᔭᐍᐏᐣ' ,
# 'ne' => 'नेपाली' ,
# 'new' => 'नेपाल भाषा' ,
# 'ja' => '日本語' ,
# 'frr' => 'Nordfriisk' ,
# 'no' => '‪Norsk (bokmål)‬' ,
# 'nn' => '‪Norsk (nynorsk)‬' ,
# 'nrm' => 'Nouormand' ,
# 'oc' => 'Occitan' ,
# 'pnb' => 'نجابی' ,
# 'pcd' => 'Picard' ,
# 'pl' => 'Polski' ,
# 'pt' => 'Português' ,
# 'ksh' => 'Ripoarisch' ,
# 'ro' => 'Română' ,
# 'qu' => 'Runa Simi' ,
# 'ru' => 'Русский' ,
# 'sah' => 'Саха тыла' ,
# 'sq' => 'Shqip' ,
# 'scn' => 'Sicilianu' ,
# 'si' => 'සිංහල' ,
# 'simple' => 'Simple English' ,
# 'sk' => 'Slovenčina' ,
# 'sl' => 'Slovenščina' ,
# 'szl' => 'Ślůnski' ,
# 'so' => 'Soomaaliga' ,
# 'srn' => 'Sranantongo' ,
# 'sr' => 'Српски / Srpski' ,
# 'sh' => 'Srpskohrvatski / Српскохрватски' ,
# 'su' => 'Basa Sunda' ,
# 'fi' => 'Suomi' ,
# 'sv' => 'Svenska' ,
# 'ta' => 'தமிழ்' ,
# 'te' => 'తెలుగు' ,
# 'th' => 'ไทย' ,
# 'tg' => 'Тоик' ,
# 'chr' => 'ᏣᎳᎩ' ,
# 'tr' => 'Türkçe' ,
# 'udm' => 'Удмурт' ,
# 'uk' => 'Українська' ,
# 'ur' => 'اردو' ,
# 'za' => 'Vahcuengh' ,
# 'vi' => 'Tiếng Việt' ,
# 'fiu-vro' => 'Võro' ,
# 'vls' => 'West-Vlams' ,
# 'war' => 'Winaray' ,
# 'wuu' => '吴语' ,
# 'yi' => 'יידיש' ,
# 'zh-yue' => '粵語' ,
# 'diq' => 'Zazaki' ,
# 'bat-smg' => 'Žemaitėška' ,
# 'zh-TW' => '中文（繁體）' ,
# 'zh-CN' => '中文（简体）' ,
# en => "English",
# 'tl' => 'Tagalog',
# );

our %lang2name = (

# Recycled from old list

'ar' => 'العربية',
'arz' => 'مصرى',
'be-x-old' => '‪Беларуская (тарашкевіца)‬',
'fa' => 'فارسی',
'ha' => 'هَوُسَ',
'he' => 'עברית',
'ku' => 'Kurdî',
'nn' => '‪Norsk (nynorsk)‬',
'pnb' => 'نجابی',
'ur' => 'اردو',
'yi' => 'יידיש',
'zh-CN' => '简体中文',
'zh-TW' => '繁體中文',

# From Wikipedia www.wikipedia.org

'ab' => 'Аҧсуа',
'ace' => 'Bahsa Acèh',
'af' => 'Afrikaans',
'ak' => 'Akan',
'als' => 'Alemannisch',
'am' => 'አማርኛ',
'an' => 'Aragonés',
'ang' => 'Ænglisc',
'as' => 'অসমীযা়',
'ast' => 'Asturianu',
'av' => 'Авар',
'ay' => 'Aymar',
'az' => 'Azərbaycanca',
'ba' => 'Башҡортса',
'bar' => 'Boarisch',
'bat-smg' => 'Žemaitėška',
'bcl' => 'Bikol Central',
'be' => 'Беларуская (Акадэмічная)',
'be-tarask' => 'Беларуская (Тарашкевіца)',
'bg' => 'Български',
'bh' => 'भोजपुरी',
'bi' => 'Bislama',
'bjn' => 'Bahasa Banjar',
'bm' => 'Bamanankan',
'bn' => 'বাংলা',
'bo' => 'བོད་ཡིག',
'bpy' => 'বিষ্ণুপ্রিয়া মণিপুরী',
'br' => 'Brezhoneg',
'bs' => 'Bosanski',
'bug' => 'ᨅᨔ ᨕᨙᨁᨗ / Basa Ugi',
'bxr' => 'Буряад',
'ca' => 'Català',
'cbk-zam' => 'Chavacano de Zamboanga',
'cdo' => 'Mìng-dĕ̤ng-ngṳ̄',
'ce' => 'Нохчийн',
'ceb' => 'Sinugboanong Binisaya',
'ch' => 'Chamoru',
'chr' => 'ᏣᎳᎩ',
'chy' => 'Tsėhesenėstsestotse',
'co' => 'Corsu',
'cr' => 'Nēhiyawēwin / ᓀᐦᐃᔭᐍᐏᐣ',
'crh' => 'Qırımtatarca',
'cs' => 'Čeština',
'csb' => 'Kaszëbsczi',
'cu' => 'Словѣ́ньскъ / ⰔⰎⰑⰂⰡⰐⰠⰔⰍⰟ',
'cv' => 'Чӑвашла',
'cy' => 'Cymraeg',
'da' => 'Dansk',
'de' => 'Deutsch',
'diq' => 'Zazaki',
'dsb' => 'Dolnoserbski',
'dz' => 'རྫོང་ཁ',
'ee' => 'Eʋegbe',
'el' => 'Ελληνικά',
'eml' => 'Emigliàn–Rumagnòl',
'en' => 'English',
'eo' => 'Esperanto',
'es' => 'Español',
'et' => 'Eesti',
'eu' => 'Euskara',
'ext' => 'Estremeñu',
'ff' => 'Fulfulde',
'fi' => 'Suomi',
'fiu-vro' => 'Võro',
'fj' => 'Na Vosa Vaka-Viti',
'fo' => 'Føroyskt',
'fr' => 'Français',
'frp' => 'Arpitan',
'frr' => 'Nordfriisk',
'fur' => 'Furlan',
'fy' => 'Frysk',
'ga' => 'Gaeilge',
'gag' => 'Gagauz',
'gan' => '贛語',
'gd' => 'Gàidhlig',
'gl' => 'Galego',
'gn' => 'Avañe’ẽ',
'gom' => 'कोंकणी / Konknni',
'got' => '𐌲𐌿𐍄𐌹𐍃𐌺',
'gu' => 'ગુજરાતી',
'gv' => 'Gaelg',
'hak' => 'Hak-kâ-fa / 客家話',
'haw' => 'ʻŌlelo Hawaiʻi',
'hi' => 'हिन्दी',
'hif' => 'Fiji Hindi',
'hr' => 'Hrvatski',
'hsb' => 'Hornjoserbsce',
'ht' => 'Kreyòl Ayisyen',
'hu' => 'Magyar',
'hy' => 'Հայերեն',
'ia' => 'Interlingua',
'id' => 'Bahasa Indonesia',
'ie' => 'Interlingue',
'ig' => 'Igbo',
'ik' => 'Iñupiak',
'ilo' => 'Ilokano',
'io' => 'Ido',
'is' => 'Íslenska',
'it' => 'Italiano',
'iu' => 'ᐃᓄᒃᑎᑐᑦ / Inuktitut',
'ja' => '日本語',
'jbo' => 'lojban',
'jv' => 'Jawa',
'ka' => 'ქართული',
'kaa' => 'Qaraqalpaqsha',
'kab' => 'Taqbaylit',
'kbd' => 'Адыгэбзэ',
'kg' => 'Kongo',
'ki' => 'Gĩkũyũ',
'kl' => 'Kalaallisut',
'km' => 'ភាសាខ្មែរ',
'kn' => 'ಕನ್ನಡ',
'ko' => '한국어',
'koi' => 'Перем Коми',
'krc' => 'Къарачай–Малкъар',
'ksh' => 'Ripoarisch',
'kv' => 'Коми',
'kw' => 'Kernewek',
'ky' => 'Кыргызча',
'la' => 'Latina',
'lb' => 'Lëtzebuergesch',
'lbe' => 'Лакку',
'lez' => 'Лезги',
'lg' => 'Luganda',
'li' => 'Limburgs',
'lij' => 'Lìgure',
'lmo' => 'Lumbaart',
'ln' => 'Lingála',
'lo' => 'ພາສາລາວ',
'lt' => 'Lietuvių',
'ltg' => 'Latgaļu',
'lv' => 'Latviešu',
'mai' => 'मैथिली',
'map-bms' => 'Basa Banyumasan',
'mdf' => 'Мокшень',
'mg' => 'Malagasy',
'mhr' => 'Олык Марий',
'mi' => 'Māori',
'min' => 'Bahaso Minangkabau',
'mk' => 'Македонски',
'ml' => 'മലയാളം',
'mn' => 'Монгол',
'mr' => 'मराठी',
'mrj' => 'Кырык Мары',
'ms' => 'Bahasa Melayu',
'mt' => 'Malti',
'mwl' => 'Mirandés',
'my' => 'မြန်မာဘာသာ',
'myv' => 'Эрзянь',
'na' => 'Dorerin Naoero',
'nah' => 'Nāhuatlahtōlli',
'nap' => 'Nnapulitano',
'nds' => 'Plattdüütsch',
'nds-nl' => 'Nedersaksisch',
'ne' => 'नेपाली',
'new' => 'नेपाल भाषा',
'nl' => 'Nederlands',
'no' => 'Nynorsk',
'nov' => 'Novial',
'nrm' => 'Nouormand / Normaund',
'nso' => 'Sesotho sa Leboa',
'nv' => 'Diné Bizaad',
'ny' => 'Chichewa',
'oc' => 'Occitan',
'om' => 'Afaan Oromoo',
'or' => 'ଓଡି଼ଆ',
'os' => 'Ирон æвзаг',
'pa' => 'ਪੰਜਾਬੀ (ਗੁਰਮੁਖੀ)',
'pag' => 'Pangasinán',
'pam' => 'Kapampangan',
'pap' => 'Papiamentu',
'pcd' => 'Picard',
'pdc' => 'Deitsch',
'pfl' => 'Pfälzisch',
'pi' => 'पाऴि',
'pih' => 'Norfuk / Pitkern',
'pl' => 'Polski',
'pms' => 'Piemontèis',
'pnt' => 'Ποντιακά',
'pt' => 'Português',
'qu' => 'Runa Simi',
'rm' => 'Rumantsch',
'rmy' => 'Romani',
'rn' => 'Kirundi',
'ro' => 'Română',
'roa-rup' => 'Armãneashce',
'roa-tara' => 'Tarandíne',
'ru' => 'Русский',
'rue' => 'Русиньскый Язык',
'rw' => 'Kinyarwanda',
'sa' => 'संस्कृतम्',
'sah' => 'Саха Тыла',
'sc' => 'Sardu',
'scn' => 'Sicilianu',
'sco' => 'Scots',
'se' => 'Davvisámegiella',
'sg' => 'Sängö',
'sh' => 'Srpskohrvatski / Српскохрватски',
'si' => 'සිංහල',
'simple' => 'Simple English',
'sk' => 'Slovenčina',
'sl' => 'Slovenščina',
'sm' => 'Gagana Sāmoa',
'sn' => 'ChiShona',
'so' => 'Soomaaliga',
'sq' => 'Shqip',
'sr' => 'Српски / Srpski',
'srn' => 'Sranantongo',
'ss' => 'SiSwati',
'st' => 'Sesotho',
'stq' => 'Seeltersk',
'su' => 'Basa Sunda',
'sv' => 'Svenska',
'sw' => 'Kiswahili',
'szl' => 'Ślůnski',
'ta' => 'தமிழ்',
'te' => 'తెలుగు',
'tet' => 'Tetun',
'tg' => 'Тоҷикӣ',
'th' => 'ภาษาไทย',
'ti' => 'ትግርኛ',
'tk' => 'Türkmençe',
'tl' => 'Tagalog',
'tn' => 'Setswana',
'to' => 'faka Tonga',
'tpi' => 'Tok Pisin',
'tr' => 'Türkçe',
'ts' => 'Xitsonga',
'tt' => 'Татарча / Tatarça',
'tum' => 'chiTumbuka',
'tw' => 'Twi',
'ty' => 'Reo Mā’ohi',
'tyv' => 'Тыва дыл',
'udm' => 'Удмурт',
'uk' => 'Українська',
'uz' => 'Oʻzbekcha / Ўзбекча',
've' => 'Tshivenḓa',
'vec' => 'Vèneto',
'vep' => 'Vepsän',
'vi' => 'Tiếng Việt',
'vls' => 'West-Vlams',
'vo' => 'Volapük',
'wa' => 'Walon',
'war' => 'Winaray',
'wo' => 'Wolof',
'wuu' => '吳語',
'xal' => 'Хальмг',
'xh' => 'isiXhosa',
'xmf' => 'მარგალური',
'yo' => 'Yorùbá',
'za' => 'Cuengh',
'zea' => 'Zeêuws',
'zh' => '中文',
'zh-classical' => '文言',
'zh-min-nan' => 'Bân-lâm-gú / Hō-ló-oē',
'zh-yue' => '粵語',
'zu' => 'isiZulu',

);



sub get_lang_name
{
    my ($lang) = @_;
    # doesn't work for now.
    my $name = $lang2name{$lang};
    if (! $name) {
        $name = $lang;
    }
    return $name;
}



sub trans_to_json_file
{
    my ($trans_file, $json_file) = @_;
    my $translations = read_translations_table ($trans_file);
    my $json = create_json ($translations, indent => 1, sort => 1);
    open my $out, ">:encoding(utf8)", $json_file
        or croak "open $json_file: $!";
    print $out $json;
    close $out or die $!;
}

1;
