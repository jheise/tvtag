#!/usr/bin/ruby

require "open-uri"
require "rexml/document"
require "uri"
require "fileutils"
require "rubygems"
require "parseconfig"

#$apikey = "D93D277140AE87F9"
$targetdir
$sourcedir
$apikey
$transfermethod = "mv"
$ignorelist = [".","..",".data.xml",".metadata",".DS_Store"]

# hold data for show
$currentshow
$currentdoc 

# hold changes
$changes = []

def getSeriesID( name )
    readonce = 0
    showid = ""
    doc = ""
    if File.exist? "#{$targetdir}/#{name}/.metadata"
        open "#{$targetdir}/#{name}/.metadata" do |f|
            showid = f.read.chomp
        end
    else
        open "http://thetvdb.com/api/GetSeries.php?seriesname=#{URI.escape(name)}","User-Agent" => "ruby/#{RUBY_VERSION}" do |f|
            doc = REXML::Document.new f
            
            doc.elements.each "Data/Series/seriesid" do |seriesid|
                showid = seriesid.text
                readonce += 1
            end
        end
        if readonce == 1
            return showid 
        else
            puts doc
            abort "Series #{name} resolves to multiple shows"
        end
    end
end

def getDataTVDB(target,seriesid)
    open( target,"w") do |f|
        open "http://thetvdb.com/api/#{$apikey}/series/#{seriesid}/all/","User-Agent" => "ruby/#{RUBY_VERSION}" do |tvdb|
            f.write tvdb.read
        end
    end
end

def getData(show)
    data = {}
    unless File.exist? $targetdir
        Dir.mkdir $targetdir
    end
    unless File.exist? "#{$targetdir}/#{show}"
        Dir.mkdir "#{$targetdir}/#{show}"
    end
    unless File.exist? "#{$targetdir}/#{show}/.data.xml"
        series = show
        seriesid = getSeriesID series 
        getDataTVDB("#{$targetdir}/#{show}/.data.xml",seriesid)
    end
    open "#{$targetdir}/#{show}/.data.xml" do |f|
        doc = REXML::Document.new f
        doc.elements.each "Data/Episode" do |episode|
            seasonnumber,episodenumber,episodename = ""
            episode.elements.each "SeasonNumber" do |seasonid|
                seasonnumber = seasonid.text
            end
            episode.elements.each "EpisodeNumber" do |episodenum|
                episodenumber = episodenum.text
            end
            episode.elements.each "EpisodeName" do |epiname|
                episodename = epiname.text
            end
            unless data.keys.include? seasonnumber
                data[seasonnumber] = {}
            end
            data[seasonnumber][episodenumber] = episodename
        end
    end
    return data
end

def getTVTitle(season,episode)
    if $currentdoc.keys.include? season
        if $currentdoc[season].keys.include? episode
            return $currentdoc[season][episode]
        end
        raise "couldnt not find episode #{episode} in season #{season}"
    end
    raise "could not find #{season}"
end

def handleEpisode( episode )
    if episode =~ /^.*\/(.*)\.[sS](\d\d)[eE](\d\d)\..*\.(\w*)$/
        show = $1
        seaLabel = $2
        seaSearch = $2
        epLabel  = $3
        epSearch = $3
        filetype = $4
        if seaSearch =~ /0(\d)/
            seaSearch = $1
        end
        if epSearch =~ /0(\d)/
            epSearch = $1
        end
        show = show.gsub "."," "
        puts "show is #{show}"
        puts "season is #{seaSearch}"
        puts "episode number is #{epSearch}"
        unless $currentshow == show
            $currentdoc = getData show
            $currentshow = show
        end
        begin 
            title = getTVTitle(seaSearch,epSearch)
        rescue 
            #abort "#{episode} is not listed in data"
            File.delete "#{$targetdir}/#{show}/.data.xml"
            $currentdoc = getData show
            title = getTVTitle(seaSearch,epSearch)
        end
        destination = "#{$targetdir}/#{show}/Season #{seaSearch}"
        unless File.exist? destination
            Dir.mkdir destination
        end
        $changes.push [episode,"#{destination}/#{seaSearch}x#{epLabel} - #{title}.#{filetype}"]
    end
end

def checkItem( item )
    if File.directory? item
        return "directory"
    elsif  item =~ /^.*\.S\d\dE\d\d\..*\.\w*$/
        return "raw"
    end
end

def searchDirectory( dir )
    puts "parsing dir #{dir}"
    Dir.foreach dir do |item|
        unless $ignorelist.include? item
            itemresult = checkItem "#{dir}/#{item}"
            case itemresult
            when "directory"
                searchDirectory "#{dir}/#{item}"
            when "raw"
                puts "found episode #{item}"
                handleEpisode "#{dir}/#{item}"
            end
        end
    end
end

            

conf = ParseConfig.new "tag.config"
$apikey = conf.get_value "apikey"
$targetdir = conf.get_value "targetdir"
$sourcedir = conf.get_value "sourcedir"
$transfermethod = conf.get_value "transfermethod"

searchDirectory $sourcedir

$changes.each do |episode|
    #puts "#{$transfermethod} \"#{episode[0]}\" \"#{episode[1]}\""
    #FileUtils.mv "\"#{episode[0]}\"","\"#{episode[1]}\""
    `#{$transfermethod} "#{episode[0]}" "#{episode[1]}"`
end
