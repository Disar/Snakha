package;

import kha.audio1.Audio;
import haxe.EnumTools;
import kha.Color;
import kha.input.KeyCode;
import kha.input.Keyboard;
import kha.math.Vector2;
import kha.Assets;
import kha.Framebuffer;
import kha.Scheduler;
import kha.System;
import kha.math.*;

class Main {

	public static function main() {
		System.start({title: "Project", width: 1024, height: 768}, function (_) {
			// Just loading everything is ok for small projects
			Assets.loadEverything(function () {
				new Game();
			});
		});
	}
}

@:enum 
abstract  Direction(Int) from Int to Int{
	var Left = 0;
	var Right = 1;
	var Up = 2;
	var Down = 3;
}

enum TileInfo{
	Empty;
	Occupied;
	Item(type:ItemType);
}


@:enum 
abstract ItemType(Int) from Int to Int{
	var death = -1;
	var bug = 0;
	var frog = 1;
	var rat = 2;
	var chicken = 3;
}

class Game{
	var gridSize:Vector2i = new Vector2i(30,30);
	var tileSize:Int = 20;
	var centroid:Vector2i = new Vector2i(0,0);
	var snakes:Array<Snake> = [];
	var deathPile:Array<Int> = [];
	var tiles:Array<TileInfo> = [];
	var scores:Array<Int> = [];
	var items:Array<Vector2i> = [];
	var itemTickUp:Float = 0.01;
	var maxTick:Float = 0.1;
	var oldTime:Float = 0.0;
	var delta:Float = 0.0;
	var maxItems:Int = 3;
	var itemUpdateDelta:Float = 0;
	var shakeTime:Float = 0.0;

	public function new(){init();}

	function init(){

		Random.init(0);
		Scheduler.addTimeTask(function () { update(); }, 0, 1 / 60);
		System.notifyOnFrames(function (frames) { render(frames); });
		Keyboard.get(0).notify(onKeyDown,onKeyUp,onKeyPress);

		for(i in 0...2){

			snakes.push(new Snake());
			snakes[i].pos.x = Std.int(Math.random()*gridSize.x);
			snakes[i].pos.y = Std.int(Math.random()*gridSize.y);
			snakes[i].dir = Random.getIn(Left-1,Down+1);
			snakes[i].tickPerSec = 0.26;
			snakes[i].length = 3;
			snakes[i].inputMap = Snake.player_input[i];

			scores.push(0);
		}

		for(i in 0...gridSize.x*gridSize.y){
			tiles.push(Empty);
		}
	}

	function update(): Void {

		var current = Scheduler.time();
		delta = current - oldTime;
		oldTime = current;

		itemUpdateDelta += delta;
		if(itemUpdateDelta > 1.0){
			updateItems();
			itemUpdateDelta -= 1.0;
		}

		var last:Vector2i;
		var snake:Snake;
		for(i in 0...snakes.length){
			snake = snakes[i];
			if(!snake.isAlive) continue;
		
			//Weird 
			last = snake.tail();
			if(last != null){setTile(last.x,last.y,Empty);}
			else{setTile(snake.pos.x,snake.pos.y,Empty);}
			//Update snakes
			if(snake.tick(delta)){

				snake.dir = snake.nextDir;
				var nextTile = correctBounds(snake.pos, tileInDirection(snake.dir));

				if(safeToPassTile(nextTile)){
					if(checkItem(i,nextTile)){
						Audio.play(Assets.sounds.combo, false);
						snake.tickPerSec -= itemTickUp;
						if(snake.tickPerSec < maxTick) snake.tickPerSec = maxTick;
					};
					snake.pos.setFrom(nextTile);
					//Update field for body
					for(i in 0...snake.length){
						setTile(snake.body[i].x,snake.body[i].y, Occupied);
					}
					//Update field for head
					setTile(snake.pos.x,snake.pos.y,Occupied);
				}
				else{
					Audio.play(Assets.sounds.bigthump, false);

					convertToFood(snake);
					snake.isAlive = false;
					shake(0.5);
				}
			}
		}

	}

	function shake(duration:Float){
		shakeTime = duration;
	}

	function convertToFood(s:Snake) : Void{
		setTile(s.pos.x,s.pos.y,Item(bug));
		items.push(new Vector2i(s.pos.x,s.pos.y));
		for(i in 0...s.length){
			setTile(s.body[i].x,s.body[i].y,Item(Random.getIn(bug, chicken)));
			items.push(new Vector2i(s.body[i].x,s.body[i].y));
			
		}
	}

	function updateItems(){

		while(items.length <= maxItems){
			var x = Std.int(Math.random() * gridSize.x);
			var y = Std.int(Math.random() * gridSize.y);

			var t = getTile(x,y);

			if(t == Empty){
				setTile(x,y,Item(Random.getIn(death+1,chicken)));
				items.push(new Vector2i(x,y));
			}
		}

		var nextPos:Vector2i;
		for(pos in items){
			var tile = getTile(pos.x,pos.y);
			switch(tile){
				case Item(type):
				var dir = Random.getIn(Left,Down);
				trace(dir);
				switch (type){
					
					case frog: 
					nextPos = tileInDirection(dir,2);
					nextPos.setFrom(correctBounds(pos, nextPos));
					if(!safeToPassTile(nextPos,false)) continue;
					setTile(pos.x,pos.y,Empty);
					pos.setFrom(nextPos);
					setTile(pos.x,pos.y,Item(frog));

					case rat: 
					nextPos = tileInDirection(dir,1);
					nextPos.setFrom(correctBounds(pos, nextPos));
					if(!safeToPassTile(nextPos,false)) continue;
					setTile(pos.x,pos.y,Empty);
					pos.setFrom(nextPos);
					setTile(pos.x,pos.y,Item(rat));

					case chicken: 
					nextPos = tileInDirection(dir,Random.getIn(1,4));
					nextPos.setFrom(correctBounds(pos, nextPos));
					if(!safeToPassTile(nextPos,false)) continue;
					setTile(pos.x,pos.y,Empty);
					pos.setFrom(nextPos);
					setTile(pos.x,pos.y,Item(chicken));

					case _:
					continue;
				}
				case _:
			}

		}
	}

	function removeItem(pos:Vector2i){
		items.remove(Lambda.find(items, function(v){
			return (v.x == pos.x && v.y == pos.y);
		}));
	}

	function safeToPassTile(pos:Vector2i, ignoreItems:Bool = true) : Bool{
			switch (getTile(pos.x,pos.y)){
				case Empty:
				return true;
				case Occupied:
				return false;
				case _:
				return ignoreItems;
			}
	}

	function checkItem(id:Int, pos:Vector2i) : Bool{
			var tile:TileInfo = getTile(pos.x,pos.y);
			
			switch(tile){
			 	case Item(type):
					switch (type){
						case death: return false;
						case bug: 
						scores[id] += 100;
						snakes[id].addToBody(1);
						removeItem(pos);
						return true;
						case frog: 
						scores[id] += 250;
						snakes[id].addToBody(1);
						removeItem(pos);
						return true;
						case rat: 
						scores[id] += 500;
						snakes[id].addToBody(1);
						removeItem(pos);
						return true;
						case chicken: 
						scores[id] += 1000;
						snakes[id].addToBody(1);
						removeItem(pos);
						return true;
					}
				case _:
				return false;
			}
	}

	function setTile(x:Int, y:Int, t:TileInfo) : Void{
		var index = x + gridSize.x*y;
		tiles[index] = t;
	}

	function getTile(x:Int, y:Int) : TileInfo{
		var index = x + gridSize.x*y;
		return tiles[index];
	}

	function correctBounds(pos:Vector2i, nextPos:Vector2i) : Vector2i{
		var limit = pos.add(nextPos);
		if(limit.x > gridSize.x-1) limit.x  = 0;
		if(limit.y > gridSize.y-1) limit.y = 0;
		if(limit.x < 0 ) limit.x = gridSize.x-1;
		if(limit.y < 0 ) limit.y = gridSize.y-1;

		return limit;
	}

	function tileInDirection(dir:Direction,multiply:Int = 1) : Vector2i{
		switch (dir){
			case Up:
			return new Vector2i(0,-1*multiply);
			case Right:
			return new Vector2i(1*multiply,0);
			case Down:
			return new Vector2i(0,1*multiply);
			case Left:
			return new Vector2i(-1*multiply,0);
		}

	}

	function setDirection(input:String){
		for(snake in snakes){
			if	(snake.dir != Right && snake.inputMap[0] == input) snake.nextDir = Left;
			else if(snake.dir != Down && snake.inputMap[1] == input) snake.nextDir = Up;
			else if(snake.dir != Up && snake.inputMap[2] == input) snake.nextDir = Down;
			else if(snake.dir != Left && snake.inputMap[3] == input) snake.nextDir = Right;
		}
	}

	function render(frames: Array<Framebuffer>): Void {
			centroid.x = Std.int(kha.System.windowWidth(0)/2) - Std.int(tileSize*gridSize.x/2);
			centroid.y = Std.int(kha.System.windowHeight(0)/2) - Std.int(tileSize*gridSize.y/2);
			var g = frames[0].g2;
			g.begin();

			for (snake in snakes){
				if(!snake.isAlive) continue;
				g.color = snake.color;
				g.fillRect(centroid.x + snake.pos.x * tileSize, centroid.y + snake.pos.y * tileSize, tileSize, tileSize);
				for(i in 0...snake.length){
					g.fillRect(centroid.x + snake.body[i].x * tileSize, centroid.y + snake.body[i].y * tileSize, tileSize, tileSize);
				}
			}
			
			var shake:Int = shakeTime > 0 ? 1:0;
			var	shakeForce = (Random.getIn(1,3)*shake);
			g.color = 0xFF999999;
			if(shake == 1) {
				shakeTime -= delta;
				g.color = Color.fromFloats(Random.getFloat(),Random.getFloat(),Random.getFloat(),1.0);

			}
			for(y in 0...gridSize.y){
				for(x in 0...gridSize.x){
					g.drawRect(shakeForce+centroid.x + x * tileSize, shakeForce+centroid.y + y*tileSize, tileSize, tileSize,2);
				}
			}
			var col:Color = 0;
			for(i in 0...tiles.length){
				switch (tiles[i]){
					case Item(type):
						switch (type){
							case death: 
							col = 0xFFFF0000;
							case bug: 
							col = 0xFFaf735f;
							case frog: 
							col = 0xFF6daf4e;
							case rat: 
							col = 0xFF999999;
							case chicken: 
							col = 0xFFFFFFFF;

						}
					g.color = col;
					g.fillRect(centroid.x + (i % gridSize.x) * tileSize, centroid.y + Std.int(i / gridSize.x) * tileSize, tileSize, tileSize);
					case Empty: continue;
					case Occupied:
					//g.fillRect(centroid.x + (i % gridSize.x) * tileSize, centroid.y + Std.int(i / gridSize.x) * tileSize, tileSize/2, tileSize/2);
				}
			}
			
			g.fontSize = 40;
			g.font = Assets.fonts.Bungee_Regular;
			
			for(i in 0...scores.length){
				g.color = snakes[i].color;
				g.drawString(Std.string(scores[i]),20,i*75+20);
				//g.drawLine(20,i*75,300,i*75,2);
			}
			g.end();
	}



	function onKeyDown(k:KeyCode) : Void{}
	function onKeyUp(k:KeyCode) : Void{}
	function onKeyPress(s:String) : Void{setDirection(s);}
}

class Snake{

	public static var player_input =  [['a','w','s','d'],['h','u','j','k']];

	public function new(){
		for(i in 0...300){
			body[i] = new Vector2i(0,0);
		}
	}
	public var isAlive:Bool = true;
	public var color:Color = Color.fromFloats(Math.random(),Math.random(),Math.random(),1.0);
	public var length:Int = 10;
	public var tickPerSec:Float = 0.1;
	public var dir:Direction = Down;
	public var nextDir:Direction = Down; //input buffer
	public var pos:Vector2i = new Vector2i();
	public var body:Array<Vector2i> = [];
	public var inputMap = player_input[0];
	var tickDelta:Float = 0.0;

	public function updateBody(){
		var i = length-1;

		while(i > 0){
			body[i].setFrom(body[i-1]);
			i--;
		}
		body[0].setFrom(pos);
	}

	public function tick(d:Float) : Bool{
		tickDelta += d;
		if(tickDelta > tickPerSec){
			tickDelta -= tickPerSec;
			updateBody();
			return true;
		}
		return false;
	}

	public function tail() : Vector2i{
		return body[length-1];
	}

	public function addToBody(l:Int) : Void{
		for(i in 0...l){
			body[length+i].setFrom(pos);
		}
		length+=l;
	}
}

// class Item{
// 	public function new(){}
// 	public var pos:Vector2i;
// 	public var tickPerSec:Float = 0.1;
// 	var tickDelta:Float = 0;

// 	public function tick(d:Float) : Bool{
// 		tickDelta+=d;
// 		if(tickDelta > tickPerSec){
// 			tickDelta -= tickPerSec;
// 			return true;
// 		}
// 		return false;
// 	}
// }