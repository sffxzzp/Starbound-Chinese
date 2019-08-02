import os, codecs, json, re, sys

class checker:
	def __init__(self, path):
		self.output = ''
		self.main(path)
	def jsonload(self, content):
		content = content.replace('\n', '')
		try:
			content = json.loads(content)
			return True
		except:
			return False
	def transcoding(self, path):
		try:
			content = codecs.open(path, 'r', encoding='utf-8').read()
		except UnicodeDecodeError:
			self.output += 'Coding: ' + path + '\n'
		if not self.jsonload(content):
			self.output += 'JSON: ' + path + '\n'
	def main(self, path):
		exts = ['patch']
		exclude = set(['.git'])
		for root, dirs, files in os.walk(path, topdown=True):
			[dirs.remove(d) for d in list(dirs) if d in exclude]
			for f in files:
				ext = f.split('.')[-1]
				path = os.path.join(root, f)
				if ext in exts:
					self.transcoding(path)
				else:
					pass
		if self.output == '':
			self.output = 'None'
		with open('output.log', 'w') as logfile:
			logfile.write(self.output)
		if self.output != 'None':
			print(self.output)
			sys.exit(1)

if __name__ == '__main__':
	checker('.')