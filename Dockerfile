FROM jekyll/jekyll:3.8

COPY Gemfile /srv/jekyll/Gemfile
COPY Gemfile.lock /srv/jekyll/Gemfile.lock
RUN bundle install