require 'id3'

class Array
  def shuffle!
    [*0..self.size-1].reverse.each do |i|
      j = Kernel.rand(i+1)
      self[i], self[j] = self[j], self[i]
    end
    self
  end
end

class PlaylistEntry < ActiveRecord::Base
  UNPLAYED = "unplayed"
  PLAYING = "playing"

  def self.playing_track
    find_by_status(PlaylistEntry::PLAYING)
  end
  
  def self.clean_up_playlist
    find(:all).each do |entry|
      entry.destroy unless File.exist? entry.file_location
    end
  end
  
  def self.find_ready_to_play
    self.clean_up_playlist
    track_to_play = nil
    while (track = find(:first, :conditions => {:status => UNPLAYED}, :order => :id)) && track_to_play.nil?
      if track.owner_disabled?  && !Enabler.enabled.empty?
        track.destroy
      else
        track_to_play = track
      end
    end
    track_to_play
  end

  def self.find_all_ready_to_play
    self.clean_up_playlist
    find(:all, :conditions => {:status => UNPLAYED}, :order => :id)
  end

  def self.find_next_track_to_play
    return false unless PlayerStatus.continuous_play?

    track = find_ready_to_play
    return track unless track.nil?
    
    create_random!
    find_ready_to_play
  end

  def self.create_random!(params = {})
    users = [params[:user] || Enabler.all].flatten
    mp3_files = users.map { |user| Dir.glob(File.join([JUKEBOX_MUSIC_ROOT, user, "**", "*.mp3"])) }.flatten
    mp3_files -= PlaylistEntry.find_all_ready_to_play.map &:file_location
    return if mp3_files.empty?

    mp3_files.shuffle!
    (params[:number_to_create] || 1).to_i.times { create! :file_location => mp3_files.pop }
  end

  def self.skip(track_id)
    find(track_id).update_attributes! :skip => true
  end
    
  def filename
    self.file_location.split('/').last
  end

  def collection
    self.file_location.gsub(JUKEBOX_MUSIC_ROOT,'').split('/')[1]
  end

  def owner
    file_location.gsub(/#{JUKEBOX_MUSIC_ROOT}\/(\w+)\/.*/, '\1')
  end

  def owner_disabled?
    Enabler.disabled.include? owner
  end

  begin # ID3 Tag Methods
    def id3
      unless @id3
        @id3 = {}
        raw_id3 = ID3::AudioFile.new(file_location)
	tag_version = (raw_id3.tagID3v2 && raw_id3.tagID3v2['TITLE'] && (raw_id3.tagID3v2['TITLE']['text'] =~ /^\377/) == nil) ? 2 : 1
        tags = raw_id3.send :"tagID3v#{tag_version}"
	if tags
          ['TITLE','ARTIST','ALBUM','TRACKNUM'].each do |field|
	    @id3[field] = tags[field] ? (tag_version == 2 ? tags[field]['text'] : tags[field]) : ''
	  end
	end
      end
      @id3	
    end
  
    def title
      id3['TITLE']
    end

    def artist
      id3['ARTIST']
    end

    def album
      id3['ALBUM']
    end

    def track_number
      id3['TRACKNUM']
    end
  
    def to_s
      "#{title} (#{album}) - #{artist} - #{collection}"
    end
  end
  
end
